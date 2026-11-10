"""Bitwarden Password Manager (bw CLI) ラッパー。

専用 agent アカウントで `bw login --apikey` 済み (別の systemd oneshot
hermes-bw-login が担当) の bw data dir を前提に、マスターパスワードファイル
(`HERMES_BW_PASSWORD_FILE`) で unlock → sync → `bw get item <id>` を実行し、
login item の username / password を返す。item は Families org の collection
`hermes-agent` 経由で agent アカウントに共有されている前提。

セキュリティ:
- session key / マスターパスワード / item の値 / bw の stdout・stderr の生データを
  ログにも例外メッセージにも一切含めない (exit code のみ記録)。
- os.environ は変更しない。子プロセス用の最小 env を都度組み立てる。
- `bw lock` は呼ばない (同じ data dir を共有する他の並行 session を失効させるため)。
  session key は関数終了で参照を捨てるだけにする。
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

logger = logging.getLogger(__name__)

BW_TIMEOUT_SECONDS = 60
ENV_PASSWORD_FILE = "HERMES_BW_PASSWORD_FILE"
ENV_BW_SESSION = "BW_SESSION"
_PASSTHROUGH_ENV = (
    "PATH",
    "HOME",
    "XDG_CONFIG_HOME",
    "BITWARDENCLI_APPDATA_DIR",
    "TMPDIR",
)
_NOT_LOGGED_IN_MARKER = "not logged in"


class BwError(Exception):
    """bw 取得失敗。メッセージに secret 値や生の CLI 出力を含めない。"""


@dataclass(frozen=True)
class LoginCredential:
    username: str = field(repr=False)
    password: str = field(repr=False)


def get_login(item_id: str) -> LoginCredential:
    """login item の username / password を返す。"""
    if not item_id:
        raise BwError("item id is empty")
    password_file = _resolve_password_file()
    base_env = _base_env()

    session = _unlock(password_file, base_env)
    session_env = {**base_env, ENV_BW_SESSION: session}
    _sync(session_env)
    credential = _fetch_login(item_id, session_env)
    del session, session_env  # bw lock はしない (他 session を失効させるため)
    return credential


def _resolve_password_file() -> Path:
    raw = os.environ.get(ENV_PASSWORD_FILE, "").strip()
    if not raw:
        raise BwError(f"{ENV_PASSWORD_FILE} is not set")
    path = Path(raw)
    if not path.is_file() or not os.access(path, os.R_OK):
        raise BwError(f"master password file is missing or unreadable: {path}")
    return path


def _base_env() -> dict[str, str]:
    env = {k: os.environ[k] for k in _PASSTHROUGH_ENV if k in os.environ}
    env["NO_COLOR"] = "1"
    return env


def _run_bw(args: list[str], env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    label = f"bw {args[0]}" + (f" {args[1]}" if args[0] == "get" else "")
    try:
        return subprocess.run(
            ["bw", *args],
            capture_output=True,
            text=True,
            timeout=BW_TIMEOUT_SECONDS,
            check=False,
            stdin=subprocess.DEVNULL,
            env=env,
        )
    except FileNotFoundError as exc:
        raise BwError("bw binary not found in PATH") from exc
    except subprocess.TimeoutExpired as exc:
        raise BwError(f"{label} timed out after {BW_TIMEOUT_SECONDS}s") from exc


def _unlock(password_file: Path, env: dict[str, str]) -> str:
    proc = _run_bw(
        [
            "unlock",
            "--raw",
            "--nointeraction",
            "--passwordfile",
            str(password_file),
        ],
        env,
    )
    if proc.returncode != 0:
        logger.error("bw unlock failed (exit=%d)", proc.returncode)
        if _NOT_LOGGED_IN_MARKER in (proc.stderr or "").lower():
            raise BwError("bw is not logged in (run the hermes-bw-login oneshot)")
        raise BwError(f"bw unlock failed with exit code {proc.returncode}")
    session = (proc.stdout or "").strip()
    if not session:
        raise BwError("bw unlock returned an empty session key")
    return session


def _sync(session_env: dict[str, str]) -> None:
    proc = _run_bw(["sync", "--nointeraction"], session_env)
    if proc.returncode != 0:
        # キャッシュ済み vault でも get は可能なので継続する。
        logger.warning("bw sync failed (exit=%d); using cached vault", proc.returncode)


def _fetch_login(item_id: str, session_env: dict[str, str]) -> LoginCredential:
    proc = _run_bw(["get", "item", item_id, "--nointeraction"], session_env)
    if proc.returncode != 0:
        logger.error("bw get item failed (exit=%d)", proc.returncode)
        raise BwError(f"bw get item failed with exit code {proc.returncode}")
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise BwError("bw returned non-JSON output") from exc

    login = data.get("login") if isinstance(data, dict) else None
    if not isinstance(login, dict):
        raise BwError("bw item has no login username/password")
    username = login.get("username")
    password = login.get("password")
    if not (isinstance(username, str) and username and isinstance(password, str) and password):
        raise BwError("bw item has no login username/password")
    return LoginCredential(username=username, password=password)
