"""Chromium (headless=new) を CDP 経由で操作する薄いクライアント。

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
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from . import config as cfg

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


class CdpError(Exception):
    """Chromium 起動 / CDP 通信の失敗。"""


class ChromiumProcess:
    """headless Chromium プロセスと user-data-dir のライフサイクル管理。"""

    def __init__(self, binary: str | None = None) -> None:
        self._binary = binary or cfg.chromium_binary()
        self._proc: subprocess.Popen | None = None
        self._user_data_dir: Path | None = None

    def start(self) -> str:
        """Chromium を起動し、page target の webSocketDebuggerUrl を返す。

        途中で失敗した場合もログインセッションの cookie を含む
        user-data-dir を /tmp に残さないよう、失敗パスでは必ず stop() で
        後始末する。
        """
        resolved = shutil.which(self._binary) or self._binary
        self._user_data_dir = Path(tempfile.mkdtemp(prefix="goldpoint-chromium-"))
        args = [
            resolved,
            "--headless=new",
            "--remote-debugging-port=0",
            f"--user-data-dir={self._user_data_dir}",
            "--no-first-run",
            "--disable-gpu",
        ]
        try:
            self._proc = subprocess.Popen(
                args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
        except FileNotFoundError as exc:
            self.stop()
            raise CdpError(f"chromium binary not found: {self._binary}") from exc

        try:
            port = self._wait_for_devtools_port()
            return self._resolve_page_ws_url(port)
        except CdpError:
            self.stop()
            raise

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
        # user-data-dir にはログインセッションの cookie が残るため、
        # プロセス終了後は必ず削除する (成功・失敗パスの両方から呼ばれる)。
        if self._user_data_dir is not None:
            shutil.rmtree(self._user_data_dir, ignore_errors=True)
            self._user_data_dir = None


class CdpConnection:
    """1 tab に対する CDP JSON-RPC 接続 (Runtime.evaluate 専用)。"""

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
        if self._ws is None:
            raise CdpError("not connected")
        request_id = self._next_id
        self._next_id += 1
        payload = {
            "id": request_id,
            "method": "Runtime.evaluate",
            "params": {
                "expression": expression,
                "returnByValue": True,
                "awaitPromise": True,
            },
        }
        await self._ws.send(json.dumps(payload))
        result = await self._recv_matching(request_id)
        exception_details = result.get("exceptionDetails")
        if exception_details:
            text = exception_details.get("text", "evaluation error")
            raise CdpError(f"Runtime.evaluate failed: {text}")
        return result.get("result", {}).get("value")

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
