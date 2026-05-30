"""Hermes plugin: daily-podcast.

Tools registered:

| name                     | summary                                                      |
| ------------------------ | ------------------------------------------------------------ |
| generate_daily_episode   | 1 トピック分の今日の episode を fetch→score→summarize→TTS→RSS |
| list_topics              | topics.toml の現状一覧                                       |
| add_topic                | topics.toml にトピックを追加 (atomic write)                  |
| list_episodes            | 生成済み episode の一覧 (新しい順)                           |
| regenerate_episode       | 指定 episode を再生成 (hint 上書き可)                        |

Design principle: パイプライン本体は plugin 内 deterministic に書く。LLM
には「採点」「要約 + 翻訳」など狭い責務だけを与える。Hermes agent は
tool 呼び出しの判断と日時/トピック解決のみを担当する。
"""

from __future__ import annotations

import json
import logging
from typing import Any, Callable

logger = logging.getLogger(__name__)

TOOLSET = "daily-podcast"
EMOJI = "🎧"


def _safe_handler(name: str, fn: Callable[..., dict[str, Any]]) -> Callable[..., str]:
    """Wrap a handler to ensure it returns JSON-encoded string and never raises.

    Hermes tools must return strings; we encode dicts here and surface any
    uncaught exception as an `error` envelope so a single bad call doesn't
    take down the whole tool surface.
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
            logger.exception("daily-podcast: tool %s raised", name)
            return json.dumps(
                {
                    "error": f"{type(exc).__name__}: {exc}",
                    "tool": name,
                },
                ensure_ascii=False,
            )
        return json.dumps(result, ensure_ascii=False, default=str)

    wrapped.__name__ = f"daily_podcast_{name}"
    wrapped.__doc__ = fn.__doc__
    return wrapped


# Tool schemas — kept in this file (not OpenAPI-driven like family-inventory)
# because there is no upstream API to mirror; the tool surface is owned by us.
_TOOL_SCHEMAS: list[dict[str, Any]] = [
    {
        "name": "generate_daily_episode",
        "description": (
            "指定トピックの今日の podcast episode を生成する。"
            "ソース巡回 → 重要記事の LLM 採点 → 日本語要約 → 台本生成 → "
            "VOICEVOX で音声化 → RSS feed 更新 までを一括実行する。"
            "topic_slug は `list_topics` で得られる値を渡すこと。"
            "target_date を省略すると今日 (Asia/Tokyo) になる。"
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "topic_slug": {
                    "type": "string",
                    "description": "topics.toml に登録された topic.slug。例: hobby-models",
                },
                "target_date": {
                    "type": "string",
                    "description": "対象日 YYYY-MM-DD (Asia/Tokyo)。省略時は今日。",
                },
            },
            "required": ["topic_slug"],
            "additionalProperties": False,
        },
    },
    {
        "name": "list_topics",
        "description": "topics.toml に登録されたトピックの一覧を返す。",
        "parameters": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    },
    {
        "name": "add_topic",
        "description": (
            "新しいトピックを topics.toml に追加する。破壊的操作なので"
            "実行前にユーザーに必ず確認を取ること。"
            "\n\nsources は配列で、各要素は {type, ...} 形式。"
            "type は hackernews / bluesky / hatena / reddit のいずれか。"
            "\n\n各 type の典型形:"
            "\n- hackernews: {type:'hackernews', query:'\"local LLM\" OR \"qwen\"',"
            " min_points:5, min_comments:1}"
            "\n- hatena: {type:'hatena', tags:['LLM','機械学習','AI']} ← タグ検索が"
            " 最もノイズが少ない (推奨)。トピックに関連するはてブタグを 3-7 個"
            " 推測して渡す。"
            "\n- hatena (フリーキーワード): {type:'hatena', query:'qwen3'}"
            "\n- reddit: {type:'reddit', subreddit:'LocalLLaMA', timeframe:'day',"
            " min_score:30}"
            "\n- bluesky: {type:'bluesky', query:'#LocalLLM', lang:'ja'}"
            " (BLUESKY_HANDLE/BLUESKY_APP_PASSWORD env が無いと skip される)"
            "\n\nトピック追加後は次回 22:00 の generate-all timer で自動的に拾われる。"
            "別 timer を Nix に追加する必要はない。"
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "slug": {
                    "type": "string",
                    "description": "kebab-case の topic 識別子。例: ai-tips",
                },
                "title": {
                    "type": "string",
                    "description": "番組タイトル。例: 'AI 開発 Tips'",
                },
                "description": {
                    "type": "string",
                    "description": "番組概要 (RSS の <description> に入る)。",
                },
                "sources": {
                    "type": "array",
                    "description": "巡回ソース定義の配列。",
                    "items": {
                        "type": "object",
                        "additionalProperties": True,
                    },
                },
                "voicevox_speaker_id": {
                    "type": "integer",
                    "description": "VOICEVOX speaker id。省略時は default (四国めたんノーマル=2)。",
                },
                "target_segment_count": {
                    "type": "integer",
                    "description": "1 episode に入れるセグメント数。省略時は 5。",
                },
            },
            "required": ["slug", "title", "description", "sources"],
            "additionalProperties": False,
        },
    },
    {
        "name": "list_episodes",
        "description": "指定トピックの過去 episode を新しい順に列挙する。",
        "parameters": {
            "type": "object",
            "properties": {
                "topic_slug": {
                    "type": "string",
                    "description": "topic.slug",
                },
                "limit": {
                    "type": "integer",
                    "description": "返す件数 (default 10)。",
                },
            },
            "required": ["topic_slug"],
            "additionalProperties": False,
        },
    },
    {
        "name": "regenerate_episode",
        "description": (
            "既存 episode を再生成する。hint で要約観点を上書きできる。"
            "破壊的操作なので実行前にユーザーに必ず確認を取ること。"
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "episode_id": {
                    "type": "string",
                    "description": "list_episodes が返す id。",
                },
                "hint": {
                    "type": "string",
                    "description": "要約・採点プロンプトに追加する観点。任意。",
                },
            },
            "required": ["episode_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "generate_all_today_episodes",
        "description": (
            "topics.toml に登録された全トピックで今日の episode を一括生成する。"
            "1 件失敗しても他の topic は続行する (障害分離)。"
            "Hermes 内蔵 cron (`hermes cron create '0 22 * * *' 'generate_all_today_episodes を呼んで'`)"
            "から定期実行する想定。手動でも呼べる。"
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "target_date": {
                    "type": "string",
                    "description": "対象日 YYYY-MM-DD (Asia/Tokyo)。省略時は今日。",
                },
                "hint": {
                    "type": "string",
                    "description": "全 topic に共通の要約観点を上書きする hint。任意。",
                },
            },
            "additionalProperties": False,
        },
    },
]


def register(ctx) -> None:
    """Plugin entry point — invoked once by the Hermes plugin loader."""
    # Lazy import: heavy deps are needed only at call time, not at load time.
    # Keeps `register()` cheap even if optional deps are missing.
    try:
        from . import handlers
    except Exception:
        logger.exception(
            "daily-podcast: failed to import handlers; plugin disabled"
        )
        return

    handler_map: dict[str, Callable[..., dict[str, Any]]] = {
        "generate_daily_episode": handlers.generate_daily_episode,
        "list_topics": handlers.list_topics,
        "add_topic": handlers.add_topic,
        "list_episodes": handlers.list_episodes,
        "regenerate_episode": handlers.regenerate_episode,
        "generate_all_today_episodes": handlers.generate_all_today_episodes,
    }

    registered = 0
    for schema in _TOOL_SCHEMAS:
        name = schema["name"]
        impl = handler_map.get(name)
        if impl is None:
            logger.warning("daily-podcast: no handler for %s; skipping", name)
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
            logger.exception("daily-podcast: ctx.register_tool failed for %s", name)

    logger.info("daily-podcast: registered %d tools", registered)
