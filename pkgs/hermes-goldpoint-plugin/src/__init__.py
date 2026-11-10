"""Hermes plugin: goldpoint-meisai.

Tools registered:

| name                       | summary                                                |
| -------------------------- | ------------------------------------------------------- |
| goldpoint_fetch_statement  | GOLD POINT CARD+ の指定請求月の明細 CSV を取得し Drive に保存 |

サイト仕様のリバースエンジニアリング詳細 (ログインフォームの bot 対策、
CDP 経由のフォーム入力・CSV 取得手順など) は goldpoint.py の docstring を
参照。このファイルは register() と tool schema の定義のみを担当する。
"""

from __future__ import annotations

import json
import logging
from typing import Any, Callable

logger = logging.getLogger(__name__)

TOOLSET = "goldpoint-meisai"
EMOJI = "💳"


def _safe_handler(name: str, fn: Callable[..., dict[str, Any]]) -> Callable[..., str]:
    """Wrap a handler to ensure it returns JSON-encoded string and never raises.

    Hermes tools must return strings; we encode dicts here and surface any
    uncaught exception as an `error` envelope so a single bad call doesn't
    take down the whole tool surface. 下位モジュール (bw.py / goldpoint.py /
    gdrive.py) 側で既に secret 値を含まない安全なメッセージに変換済みの
    前提で、ここでは type/message をそのまま JSON 化するだけに留める。
    """

    def wrapped(args: dict[str, Any] | None = None, **kwargs: Any) -> str:
        merged: dict[str, Any] = {}
        if isinstance(args, dict):
            merged.update(args)
        merged.update(kwargs)
        try:
            result = fn(**merged)
        except TypeError as exc:
            # Most likely: LLM passed unknown kwargs. Surface the error
            # rather than crash so the LLM can correct on the next turn.
            return json.dumps(
                {"error": f"bad arguments for {name}: {exc}", "tool": name},
                ensure_ascii=False,
            )
        except Exception as exc:  # pragma: no cover - defensive
            logger.exception("goldpoint-meisai: tool %s raised", name)
            return json.dumps(
                {"error": f"{type(exc).__name__}: {exc}", "tool": name},
                ensure_ascii=False,
            )
        return json.dumps(result, ensure_ascii=False, default=str)

    wrapped.__name__ = f"goldpoint_meisai_{name}"
    wrapped.__doc__ = fn.__doc__
    return wrapped


_TOOL_SCHEMAS: list[dict[str, Any]] = [
    {
        "name": "goldpoint_fetch_statement",
        "description": (
            "GOLD POINT CARD+ (ヨドバシ) の利用明細 CSV を取得し、"
            "$GOLDPOINT_STATE_DIR/csv/YYYY-MM.csv に保存した上で "
            "Google Drive の家計フォルダにアップロードする。"
            "認証情報は Bitwarden Password Manager (bw CLI) から実行時に取得するため、"
            "呼び出し側 (LLM) にパスワードを渡す必要はない。"
            "seikyuym を省略すると Asia/Tokyo の当月分を取得する "
            "(毎月10日に当月分が確定する運用前提)。"
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "seikyuym": {
                    "type": "string",
                    "description": "請求月 YYYYMM (6桁数字)。省略時は当月。例: 202609",
                },
            },
            "additionalProperties": False,
        },
    },
]


def register(ctx) -> None:
    """Plugin entry point — invoked once by the Hermes plugin loader."""
    # Lazy import: heavy deps (websockets/googleapiclient 経由の依存) は
    # 呼び出し時にのみ必要なので、register() 自体は軽く保つ。
    try:
        from . import handlers
    except Exception:
        logger.exception(
            "goldpoint-meisai: failed to import handlers; plugin disabled"
        )
        return

    handler_map: dict[str, Callable[..., dict[str, Any]]] = {
        "goldpoint_fetch_statement": handlers.fetch_statement,
    }

    registered = 0
    for schema in _TOOL_SCHEMAS:
        name = schema["name"]
        impl = handler_map.get(name)
        if impl is None:
            logger.warning("goldpoint-meisai: no handler for %s; skipping", name)
            continue
        try:
            ctx.register_tool(
                name=name,
                toolset=TOOLSET,
                schema=schema,
                handler=_safe_handler(name, impl),
                emoji=EMOJI,
            )
            registered += 1
        except Exception:
            logger.exception(
                "goldpoint-meisai: ctx.register_tool failed for %s", name
            )

    logger.info("goldpoint-meisai: registered %d tools", registered)
