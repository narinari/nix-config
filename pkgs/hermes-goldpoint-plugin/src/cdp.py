"""Chromium (既定は Xvfb 上の headed) を CDP 経由で操作する薄いクライアント。

サイト仕様上の制約 (詳細は goldpoint.py の docstring を参照): GOLD POINT
CARD+ のログインフォームは JS が動的に input の type を書き換えたり隠し
トークンを埋めたりするため、HTTP 直叩きでは再現できない。実ブラウザで
Runtime.evaluate による JS 実行だけで完結させる方針で、ナビゲーションも
`location.href = ...` 代入 + `document.readyState`/URL の poll で行う
(CDP の Page.navigate 等は使わない)。

依存 `websockets` はモジュールトップで import すると、websockets が
インストールされていない環境 (CI の py_compile など) でロード自体に
失敗するため、実際に使う関数内でのみ import する。
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import shutil
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from . import config as cfg
from . import xvfb

logger = logging.getLogger(__name__)

DEVTOOLS_PORT_POLL_TIMEOUT_SECONDS = 15
DEVTOOLS_PORT_POLL_INTERVAL_SECONDS = 0.2
DEVTOOLS_TARGETS_TIMEOUT_SECONDS = 5
# CSV を base64 化した Runtime.evaluate の戻り値を受け取れるだけの余裕を持たせる。
CDP_MAX_SIZE_BYTES = 20 * 1024 * 1024
CDP_WS_OPEN_TIMEOUT_SECONDS = 30
CDP_WS_RESPONSE_TIMEOUT_SECONDS = 30
NAVIGATION_POLL_TIMEOUT_SECONDS = 20
NAVIGATION_POLL_INTERVAL_SECONDS = 0.2
CHROMIUM_VERSION_TIMEOUT_SECONDS = 10
STALE_PROFILE_FILES = (
    "DevToolsActivePort",
    "SingletonLock",
    "SingletonSocket",
    "SingletonCookie",
)
# headless Chromium の既定 UA は "HeadlessChrome/<ver>" を含み、GOLD POINT CARD+
# (Akamai) はこれを検出すると応答を返さず接続を保留し続ける。ユーザー本人の委任操作
# なので、通常の Chrome と同じ UA を名乗る。
USER_AGENT_TEMPLATE = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/{major}.0.0.0 Safari/537.36"
)
_VERSION_PATTERN = re.compile(r"(\d+)\.\d+\.\d+\.\d+")


class CdpError(Exception):
    """Chromium 起動 / CDP 通信の失敗。"""


def _user_agent(binary: str) -> str:
    """`chromium --version` のメジャー版から通常 Chrome 相当の UA を組み立てる。"""
    try:
        proc = subprocess.run(
            [binary, "--version"],
            capture_output=True,
            text=True,
            timeout=CHROMIUM_VERSION_TIMEOUT_SECONDS,
            check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
        raise CdpError(f"failed to query chromium version: {binary}") from exc
    match = _VERSION_PATTERN.search(proc.stdout or "")
    if proc.returncode != 0 or match is None:
        raise CdpError(f"could not parse chromium version: {binary}")
    return USER_AGENT_TEMPLATE.format(major=match.group(1))


def _prepare_profile_dir(persistent: Path) -> Path:
    """永続プロファイルを 0700 で用意し、前回の残りファイルを消す。"""
    persistent.mkdir(mode=0o700, parents=True, exist_ok=True)
    persistent.chmod(0o700)
    # 前回の実行が残したポート番号やロックを読むと古いポートに繋いでしまうため消す。
    for name in STALE_PROFILE_FILES:
        (persistent / name).unlink(missing_ok=True)
    return persistent


class ChromiumProcess:
    """Chromium プロセス・user-data-dir・(headed 時の) Xvfb のライフサイクル管理。

    既定は headless (通常 Chrome 相当の UA)。GOLDPOINT_HEADED=1 で Xvfb 上の headed。
    ログインの検出対策は human_input.py / 起動フラグ / 永続プロファイルで行う。
    """

    def __init__(self, binary: str | None = None) -> None:
        self._binary = binary or cfg.chromium_binary()
        self._headless = cfg.headless()
        self._proc: subprocess.Popen | None = None
        self._user_data_dir: Path | None = None
        self._display: xvfb.VirtualDisplay | None = None
        # サイト (Akamai) の信頼 cookie (_abck 等) を引き継ぐためプロファイルを使い回す。
        self._profile_dir = cfg.chromium_profile_dir()

    def start(self) -> str:
        """Chromium を起動し、page target の webSocketDebuggerUrl を返す。

        途中で失敗した場合もログインセッションの cookie を含む
        user-data-dir を /tmp に残さないよう、失敗パスでは必ず stop() で
        後始末する。
        """
        resolved = shutil.which(self._binary) or self._binary
        self._user_data_dir = _prepare_profile_dir(self._profile_dir)
        try:
            args, env = self._launch_spec(resolved)
            self._proc = subprocess.Popen(
                args, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
        except xvfb.XvfbError as exc:
            self.stop()
            raise CdpError(f"virtual display failed: {exc}") from exc
        except FileNotFoundError as exc:
            self.stop()
            raise CdpError(f"chromium binary not found: {self._binary}") from exc

        try:
            port = self._wait_for_devtools_port()
            return self._resolve_page_ws_url(port)
        except CdpError:
            self.stop()
            raise

    def _launch_spec(self, resolved: str) -> tuple[list[str], dict[str, str]]:
        """起動引数と env を返す。headed なら Xvfb を起動して DISPLAY を渡す。"""
        args = [
            resolved,
            "--remote-debugging-port=0",
            f"--user-data-dir={self._user_data_dir}",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-gpu",
            "--window-size=1366,768",
            # navigator.webdriver を立てない (自動操作フラグ)。
            "--disable-blink-features=AutomationControlled",
            "--lang=ja-JP",
            "--password-store=basic",
        ]
        env = dict(os.environ)
        if self._headless:
            # headless の既定 UA は HeadlessChrome を含み、ページ取得すら保留される。
            args += ["--headless=new", f"--user-agent={_user_agent(resolved)}"]
            return args, env
        self._display = xvfb.VirtualDisplay(cfg.xvfb_binary())
        env["DISPLAY"] = self._display.start()
        env.pop("WAYLAND_DISPLAY", None)
        args.append("--ozone-platform=x11")
        return args, env

    def _wait_for_devtools_port(self) -> int:
        assert self._user_data_dir is not None
        port_file = self._user_data_dir / "DevToolsActivePort"
        deadline = time.monotonic() + DEVTOOLS_PORT_POLL_TIMEOUT_SECONDS
        while time.monotonic() < deadline:
            if port_file.exists():
                try:
                    first_line = port_file.read_text(encoding="utf-8").splitlines()[0]
                    return int(first_line.strip())
                except (IndexError, ValueError):
                    pass
            if self._proc is not None and self._proc.poll() is not None:
                raise CdpError(f"chromium exited early (code={self._proc.returncode})")
            time.sleep(DEVTOOLS_PORT_POLL_INTERVAL_SECONDS)
        raise CdpError("timed out waiting for DevToolsActivePort")

    def _resolve_page_ws_url(self, port: int) -> str:
        url = f"http://127.0.0.1:{port}/json"
        try:
            with urllib.request.urlopen(
                url, timeout=DEVTOOLS_TARGETS_TIMEOUT_SECONDS
            ) as resp:
                targets = json.loads(resp.read().decode("utf-8"))
        except (urllib.error.URLError, json.JSONDecodeError) as exc:
            raise CdpError(f"failed to query devtools targets: {exc}") from exc
        for target in targets:
            if target.get("type") == "page" and target.get("webSocketDebuggerUrl"):
                return target["webSocketDebuggerUrl"]
        raise CdpError("no page target with webSocketDebuggerUrl found")

    def stop(self) -> None:
        if self._proc is not None and self._proc.poll() is None:
            self._proc.terminate()
            try:
                self._proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._proc.kill()
        self._proc = None
        # 永続プロファイル (0700, hermes 専用) は残す。ログアウトは呼び出し側。
        self._user_data_dir = None
        if self._display is not None:
            self._display.stop()
            self._display = None


class CdpConnection:
    """1 tab に対する CDP JSON-RPC 接続。"""

    def __init__(self, ws_url: str) -> None:
        self._ws_url = ws_url
        self._ws: Any = None
        self._next_id = 1

    async def connect(self) -> None:
        # websockets はデフォルトで Origin ヘッダを送らないため CDP 側の
        # origin チェックによる 403 は発生しない。
        import websockets

        self._ws = await websockets.connect(
            self._ws_url,
            max_size=CDP_MAX_SIZE_BYTES,
            open_timeout=CDP_WS_OPEN_TIMEOUT_SECONDS,
        )

    async def close(self) -> None:
        if self._ws is not None:
            await self._ws.close()
            self._ws = None

    async def evaluate(self, expression: str) -> Any:
        """Runtime.evaluate を returnByValue+awaitPromise で実行し value を返す。"""
        result = await self.send(
            "Runtime.evaluate",
            {"expression": expression, "returnByValue": True, "awaitPromise": True},
        )
        exception_details = result.get("exceptionDetails")
        if exception_details:
            text = exception_details.get("text", "evaluation error")
            raise CdpError(f"Runtime.evaluate failed: {text}")
        return result.get("result", {}).get("value")

    async def send(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        """任意の CDP メソッドを呼び result を返す (Input.* 等)。"""
        if self._ws is None:
            raise CdpError("not connected")
        request_id = self._next_id
        self._next_id += 1
        payload = {"id": request_id, "method": method, "params": params}
        await self._ws.send(json.dumps(payload))
        return await self._recv_matching(request_id)

    async def _recv_matching(self, request_id: int) -> dict[str, Any]:
        deadline = time.monotonic() + CDP_WS_RESPONSE_TIMEOUT_SECONDS
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise CdpError("timed out waiting for CDP response")
            try:
                raw = await asyncio.wait_for(self._ws.recv(), timeout=remaining)
            except asyncio.TimeoutError as exc:
                raise CdpError("timed out waiting for CDP response") from exc
            msg = json.loads(raw)
            if msg.get("id") == request_id:
                if "error" in msg:
                    raise CdpError(
                        f"CDP error: {msg['error'].get('message', 'unknown')}"
                    )
                return msg.get("result", {})
            # id の無いメッセージ (CDP イベント通知) は無視して待ち続ける。


class CdpSession:
    """Chromium 起動から CDP 接続までを 1 つにまとめた async context manager。"""

    def __init__(self, binary: str | None = None) -> None:
        self._chromium = ChromiumProcess(binary)
        self._conn: CdpConnection | None = None

    async def __aenter__(self) -> "CdpSession":
        # Chromium 起動〜DevToolsActivePort の poll はブロッキングなので別スレッドで実行する。
        ws_url = await asyncio.to_thread(self._chromium.start)
        self._conn = CdpConnection(ws_url)
        await self._conn.connect()
        return self

    async def __aexit__(self, *exc_info: Any) -> None:
        # close() が例外を投げても Chromium プロセス/user-data-dir の後始末
        # (cookie 削除含む) は必ず行う。
        try:
            if self._conn is not None:
                await self._conn.close()
        finally:
            self._chromium.stop()

    async def eval_js(self, expression: str) -> Any:
        assert self._conn is not None
        return await self._conn.evaluate(expression)

    async def send(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        assert self._conn is not None
        return await self._conn.send(method, params)

    async def goto(
        self, url: str, *, timeout: float = NAVIGATION_POLL_TIMEOUT_SECONDS
    ) -> None:
        # readyState だけを poll すると、遷移開始前点で旧ページが既に
        # 'complete' になっているため即座に true 判定してしまい、実際の
        # ナビゲーション完了を待たない。full page load で document が
        # 入れ替わると window のプロパティも消えることを利用した sentinel
        # 方式にする (リダイレクトが挟まっても複数回 document が入れ替わる
        # ため引き続き安全)。
        await self.eval_js("window.__gp_nav_sentinel = true")
        await self.eval_js(f"location.href = {json.dumps(url)}")
        await self.poll_js(
            "window.__gp_nav_sentinel === undefined "
            "&& document.readyState === 'complete'",
            timeout=timeout,
        )

    async def poll_js(
        self,
        expression: str,
        *,
        timeout: float,
        interval: float = NAVIGATION_POLL_INTERVAL_SECONDS,
    ) -> Any:
        """`expression` が truthy を返すまで poll する。timeout で CdpError。"""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                value = await self.eval_js(expression)
            except CdpError as exc:
                # 遷移中 (旧 document の unload 後〜新 document 構築前) に
                # evaluate すると、CDP は "Execution context was destroyed" /
                # "Cannot find default execution context" 系のエラーを返す
                # ことがある。これは poll 対象の状態とは無関係な一過性の
                # エラーなので無視して次の iteration に進む。それ以外の
                # CdpError (JS 構文エラー等) はそのまま伝播させる。
                if "context" in str(exc).lower():
                    await asyncio.sleep(interval)
                    continue
                raise
            if value:
                return value
            await asyncio.sleep(interval)
        raise CdpError(f"timed out polling js expression: {expression[:80]}")
