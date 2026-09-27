"""Plugin configuration: env 読み。

secret の実体 (ID/パスワード) はここでは持たない — 実行時に bws.py が
Bitwarden Secrets Manager から取得する。ここは「どの env / secret id を
使うか」というマッピングだけを担当する。
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

ENV_STATE_DIR = "GOLDPOINT_STATE_DIR"
ENV_DRIVE_FOLDER = "GOLDPOINT_DRIVE_FOLDER"
ENV_BWS_SECRET_ID = "GOLDPOINT_BWS_SECRET_ID"
ENV_BWS_SECRET_PASSWORD = "GOLDPOINT_BWS_SECRET_PASSWORD"
ENV_CHROMIUM = "GOLDPOINT_CHROMIUM"
ENV_BROWSER_FALLBACK = "AGENT_BROWSER_EXECUTABLE_PATH"
ENV_HERMES_HOME = "HERMES_HOME"

DEFAULT_STATE_DIR = "/var/lib/hermes-goldpoint"
DEFAULT_DRIVE_FOLDER = "家計/goldpoint"
DEFAULT_CHROMIUM_BINARY = "chromium"
DEFAULT_HERMES_HOME = "~/.hermes"


@dataclass(frozen=True)
class GoldpointEnv:
    """現在の env スナップショット (デバッグ表示用)。secret 値そのものは含めない。"""

    state_dir: Path
    drive_folder: str
    chromium: str
    hermes_home: Path
    bws_secret_id_configured: bool
    bws_secret_password_configured: bool


def state_dir() -> Path:
    return Path(os.environ.get(ENV_STATE_DIR, DEFAULT_STATE_DIR))


def csv_dir() -> Path:
    return state_dir() / "csv"


def gdrive_token_path() -> Path:
    return state_dir() / "gdrive_token.json"


def drive_folder() -> str:
    return os.environ.get(ENV_DRIVE_FOLDER, DEFAULT_DRIVE_FOLDER).strip("/")


def hermes_home() -> Path:
    raw = os.environ.get(ENV_HERMES_HOME, "").strip() or DEFAULT_HERMES_HOME
    return Path(raw).expanduser()


def google_client_secret_path() -> Path:
    # google-workspace bundled skill と共用のファイル。ここでは読むだけ。
    return hermes_home() / "google_client_secret.json"


def chromium_binary() -> str:
    """優先順位: GOLDPOINT_CHROMIUM > AGENT_BROWSER_EXECUTABLE_PATH > "chromium"。"""
    for env_name in (ENV_CHROMIUM, ENV_BROWSER_FALLBACK):
        value = os.environ.get(env_name, "").strip()
        if value:
            return value
    return DEFAULT_CHROMIUM_BINARY


def bws_secret_id() -> str | None:
    return os.environ.get(ENV_BWS_SECRET_ID, "").strip() or None


def bws_secret_password() -> str | None:
    return os.environ.get(ENV_BWS_SECRET_PASSWORD, "").strip() or None


def snapshot() -> GoldpointEnv:
    """診断表示用のスナップショット。secret 値ではなく設定有無だけを返す。"""
    return GoldpointEnv(
        state_dir=state_dir(),
        drive_folder=drive_folder(),
        chromium=chromium_binary(),
        hermes_home=hermes_home(),
        bws_secret_id_configured=bws_secret_id() is not None,
        bws_secret_password_configured=bws_secret_password() is not None,
    )
