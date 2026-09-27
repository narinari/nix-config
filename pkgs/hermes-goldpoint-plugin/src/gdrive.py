"""Google Drive アップロード (drive v3, scope: drive.file のみ)。

token: `$GOLDPOINT_STATE_DIR/gdrive_token.json` (refresh したら書き戻す)。
client secret: `$HERMES_HOME/google_client_secret.json`
(google-workspace bundled skill と共用、ここでは読むだけ)。

依存 `googleapiclient` / `google.oauth2` / `google.auth` はモジュールトップ
で import すると、ライブラリ未インストールの環境 (py_compile など) で
ロード自体に失敗するため、実際に使う関数内でのみ import する。
"""

from __future__ import annotations

import json
import logging
from typing import Any

from . import config as cfg

logger = logging.getLogger(__name__)

DRIVE_FILE_SCOPE = "https://www.googleapis.com/auth/drive.file"
FOLDER_MIME_TYPE = "application/vnd.google-apps.folder"


class GDriveError(Exception):
    """Drive 認可未完了 / API エラーなど。token の中身は含めない。"""


def _load_credentials() -> Any:
    from google.auth.exceptions import RefreshError
    from google.auth.transport.requests import Request
    from google.oauth2.credentials import Credentials

    token_path = cfg.gdrive_token_path()
    if not token_path.exists():
        raise GDriveError(
            "gdrive token not found; run gdrive_setup.py --auth-url / --auth-code first"
        )
    data = json.loads(token_path.read_text(encoding="utf-8"))
    creds = Credentials.from_authorized_user_info(data, scopes=[DRIVE_FILE_SCOPE])
    if creds.expired and creds.refresh_token:
        try:
            creds.refresh(Request())
        except RefreshError as exc:
            # token 値は含めない。refresh_token が失効/取り消された場合の典型経路。
            raise GDriveError(
                "token refresh failed (RefreshError); "
                "run gdrive_setup.py --auth-url / --auth-code again"
            ) from exc
        _save_credentials(creds)
    return creds


def _save_credentials(creds: Any) -> None:
    token_path = cfg.gdrive_token_path()
    token_path.parent.mkdir(parents=True, exist_ok=True)
    token_path.write_text(creds.to_json(), encoding="utf-8")


def _build_service() -> Any:
    from googleapiclient.discovery import build

    creds = _load_credentials()
    return build("drive", "v3", credentials=creds, cache_discovery=False)


def _execute(request: Any) -> Any:
    """`request.execute()` を実行し、`HttpError` を `GDriveError` に変換する。

    handlers.py 側は `except gdrive.GDriveError` でしか拾わないため、ここで
    変換しないと 401/403/404 等が素通りして hint (gdrive_setup.py の案内) が
    出なくなる。元例外の型名と status code のみ含め、token 値は含めない。
    """
    from googleapiclient.errors import HttpError

    try:
        return request.execute()
    except HttpError as exc:
        status = getattr(exc, "status_code", None)
        if status is None:
            status = getattr(getattr(exc, "resp", None), "status", None)
        raise GDriveError(f"Drive API error (HttpError, status={status})") from exc


def ensure_folder_path(folder_path: str) -> str:
    """`家計/goldpoint` のような `/` 区切りパスをマイドライブ直下から辿り、
    無ければ作成して最終フォルダの id を返す。"""
    service = _build_service()
    parent_id = "root"
    for name in [p for p in folder_path.split("/") if p]:
        parent_id = _find_or_create_folder(service, name=name, parent_id=parent_id)
    return parent_id


def _find_or_create_folder(service: Any, *, name: str, parent_id: str) -> str:
    query = (
        f"name = {_escape_query(name)} and mimeType = '{FOLDER_MIME_TYPE}' "
        f"and '{parent_id}' in parents and trashed = false"
    )
    resp = _execute(
        service.files().list(q=query, spaces="drive", fields="files(id, name)")
    )
    files = resp.get("files") or []
    if files:
        return files[0]["id"]

    metadata = {"name": name, "mimeType": FOLDER_MIME_TYPE, "parents": [parent_id]}
    created = _execute(service.files().create(body=metadata, fields="id"))
    return created["id"]


def upload_or_replace(
    *, folder_id: str, filename: str, content: bytes, mimetype: str
) -> dict[str, str]:
    """同名ファイルがあれば files().update で上書き、無ければ create。{id, name} を返す。"""
    from googleapiclient.http import MediaInMemoryUpload

    service = _build_service()
    query = (
        f"name = {_escape_query(filename)} and '{folder_id}' in parents "
        "and trashed = false"
    )
    resp = _execute(
        service.files().list(q=query, spaces="drive", fields="files(id, name)")
    )
    files = resp.get("files") or []
    media = MediaInMemoryUpload(content, mimetype=mimetype, resumable=False)

    if files:
        file_id = files[0]["id"]
        updated = _execute(
            service.files().update(fileId=file_id, media_body=media, fields="id, name")
        )
        return {"id": updated["id"], "name": updated["name"]}

    metadata = {"name": filename, "parents": [folder_id]}
    created = _execute(
        service.files().create(body=metadata, media_body=media, fields="id, name")
    )
    return {"id": created["id"], "name": created["name"]}


def _escape_query(name: str) -> str:
    """Drive API の `q` パラメータ用に文字列リテラルをエスケープする。"""
    escaped = name.replace("\\", "\\\\").replace("'", "\\'")
    return f"'{escaped}'"
