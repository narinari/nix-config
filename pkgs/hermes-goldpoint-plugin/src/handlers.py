"""Tool handler: goldpoint_fetch_statement。

GOLD POINT CARD+ の利用明細 CSV を取得して Drive にアップロードする。
サイト仕様の詳細 (bot 対策・CDP 手順など) は goldpoint.py の docstring を
参照。ここでは資格情報の取り出し (bws) → 取得 (goldpoint) → 保存/アップ
ロード (gdrive) のオーケストレーションだけを行う。

セキュリティ: password / BWS secret 値 / CSV バイト列そのものは、戻り値
にも例外メッセージにも含めない。
"""

from __future__ import annotations

import logging
import re
from datetime import datetime
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

from . import bws
from . import config as cfg
from . import gdrive
from . import goldpoint

logger = logging.getLogger(__name__)

SEIKYUYM_PATTERN = re.compile(r"^\d{6}$")
DEFAULT_TIMEZONE = "Asia/Tokyo"
CSV_MIMETYPE = "text/csv"


class _MissingSecretConfig(Exception):
    """GOLDPOINT_BWS_SECRET_ID / GOLDPOINT_BWS_SECRET_PASSWORD 未設定。"""


def fetch_statement(
    *,
    seikyuym: str | None = None,
    # Hermes runtime injects metadata kwargs (task_id, etc) that aren't part
    # of the tool schema. Absorb them so the handler doesn't TypeError.
    **_: Any,
) -> dict[str, Any]:
    """指定請求月 (YYYYMM) の明細 CSV を取得し、保存 + Drive アップロードする。"""
    resolved_seikyuym = seikyuym or _current_seikyuym()
    if not SEIKYUYM_PATTERN.match(resolved_seikyuym):
        return {
            "error": f"invalid seikyuym: {resolved_seikyuym!r}",
            "hint": "YYYYMM 形式の6桁数字で指定してください (例: 202609)",
        }

    try:
        auth_key, password = _load_credentials()
    except (bws.BwsError, _MissingSecretConfig) as exc:
        return {
            "error": f"failed to load credentials: {exc}",
            "hint": (
                "GOLDPOINT_BWS_SECRET_ID / GOLDPOINT_BWS_SECRET_PASSWORD / "
                "BWS_ACCESS_TOKEN の設定 (agenix) を確認してください"
            ),
        }

    try:
        csv_bytes = goldpoint.fetch_statement_csv(
            auth_key=auth_key, password=password, seikyuym=resolved_seikyuym
        )
    except goldpoint.GoldpointError as exc:
        return {
            "error": f"goldpoint statement fetch failed: {exc}",
            "hint": "ログイン情報 / サイト側の仕様変更 / Chromium 起動失敗を確認してください",
        }

    saved_path = _save_csv(resolved_seikyuym, csv_bytes)
    rows = csv_bytes.decode("cp932", errors="replace").count("\n")

    try:
        folder_id = gdrive.ensure_folder_path(cfg.drive_folder())
        uploaded = gdrive.upload_or_replace(
            folder_id=folder_id,
            filename=saved_path.name,
            content=csv_bytes,
            mimetype=CSV_MIMETYPE,
        )
    except gdrive.GDriveError as exc:
        return {
            "error": f"Drive upload failed: {exc}",
            "hint": "gdrive_setup.py --check / --auth-url を実行して認可してください",
            "seikyuym": resolved_seikyuym,
            "saved_path": str(saved_path),
            "bytes": len(csv_bytes),
            "rows": rows,
        }

    return {
        "seikyuym": resolved_seikyuym,
        "saved_path": str(saved_path),
        "drive_folder": cfg.drive_folder(),
        "drive_file": uploaded["name"],
        "drive_file_id": uploaded["id"],
        "bytes": len(csv_bytes),
        "rows": rows,
    }


def _load_credentials() -> tuple[str, str]:
    secret_id_auth = cfg.bws_secret_id()
    secret_id_password = cfg.bws_secret_password()
    if not secret_id_auth or not secret_id_password:
        raise _MissingSecretConfig(
            "GOLDPOINT_BWS_SECRET_ID / GOLDPOINT_BWS_SECRET_PASSWORD is not set"
        )
    auth_key = bws.get_secret_value(secret_id_auth)
    password = bws.get_secret_value(secret_id_password)
    return auth_key, password


def _current_seikyuym() -> str:
    now = datetime.now(ZoneInfo(DEFAULT_TIMEZONE))
    return now.strftime("%Y%m")


def _save_csv(seikyuym: str, content: bytes) -> Path:
    csv_dir = cfg.csv_dir()
    csv_dir.mkdir(parents=True, exist_ok=True)
    filename = f"{seikyuym[:4]}-{seikyuym[4:]}.csv"
    path = csv_dir / filename
    path.write_bytes(content)
    return path
