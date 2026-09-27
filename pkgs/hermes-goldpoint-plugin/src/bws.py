"""Bitwarden Secrets Manager (bws CLI) ラッパー。

`bws secret get <secret-id> --output json` を subprocess で呼び `.value` を
返す。認証は環境変数 `BWS_ACCESS_TOKEN` 経由 (agenix で供給済み前提、ここでは
存在確認のみ行う)。bws バイナリは PATH にある前提 (extraPackages で供給)。

セキュリティ: 取得した secret 値・bws の stdout/stderr の生データを、ログにも
例外メッセージにも一切含めない。
"""

from __future__ import annotations

import json
import logging
import os
import subprocess

logger = logging.getLogger(__name__)

BWS_TIMEOUT_SECONDS = 30
ENV_ACCESS_TOKEN = "BWS_ACCESS_TOKEN"


class BwsError(Exception):
    """bws secret 取得失敗。メッセージに secret 値や生の CLI 出力を含めない。"""


def get_secret_value(secret_id: str) -> str:
    """`bws secret get <id> --output json` を実行し `.value` を返す。"""
    if not secret_id:
        raise BwsError("secret id is empty")
    if not os.environ.get(ENV_ACCESS_TOKEN, "").strip():
        raise BwsError(f"{ENV_ACCESS_TOKEN} is not set")

    try:
        proc = subprocess.run(
            ["bws", "secret", "get", secret_id, "--output", "json"],
            capture_output=True,
            text=True,
            timeout=BWS_TIMEOUT_SECONDS,
            check=False,
        )
    except FileNotFoundError as exc:
        raise BwsError("bws binary not found in PATH") from exc
    except subprocess.TimeoutExpired as exc:
        raise BwsError(
            f"bws secret get timed out after {BWS_TIMEOUT_SECONDS}s"
        ) from exc

    if proc.returncode != 0:
        # stderr には secret id やヒントしか出ない想定だが、念のため生データは
        # ログにも例外にも出さず exit code のみ記録する。
        logger.error("bws secret get failed (exit=%d)", proc.returncode)
        raise BwsError(f"bws secret get failed with exit code {proc.returncode}")

    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise BwsError("bws returned non-JSON output") from exc

    value = data.get("value")
    if not isinstance(value, str) or not value:
        raise BwsError("bws secret has no value")
    return value
