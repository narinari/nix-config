"""Compose the podcast script (a sequence of utterances) from selected items.

A script is a list of `Utterance` dicts: `{ role, text, pause_after_ms }`.
This list feeds VOICEVOX synth; roles map to speaker IDs in `voicevox.py`.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import date as date_cls
from typing import Any

from . import config as cfg

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class Utterance:
    role: str
    text: str
    pause_after_ms: int = 400

    def as_dict(self) -> dict[str, Any]:
        return {
            "role": self.role,
            "text": self.text,
            "pause_after_ms": self.pause_after_ms,
        }


def compose_script(
    topic: cfg.TopicConfig,
    target_date: date_cls,
    items: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Return a flat list of utterance dicts (the 'script')."""
    utterances: list[Utterance] = []
    date_label = f"{target_date.year}年{target_date.month}月{target_date.day}日"

    utterances.append(
        Utterance(
            role="host",
            text=(
                f"こんにちは、{topic.title} へようこそ。"
                f"今日は {date_label} の気になるトピックを{len(items)}本お届けします。"
            ),
            pause_after_ms=600,
        )
    )

    for i, item in enumerate(items, start=1):
        summary_ja = (item.get("summary_ja") or item.get("title") or "").strip()
        takeaway = (item.get("takeaway_ja") or "").strip()
        title = (item.get("title") or "").strip()
        source = item.get("source") or ""
        utterances.append(
            Utterance(
                role="host",
                text=f"{i}本目。{title}。出典は {_label_source(source)} です。",
                pause_after_ms=400,
            )
        )
        if summary_ja:
            utterances.append(
                Utterance(role="host", text=summary_ja, pause_after_ms=500)
            )
        if takeaway:
            utterances.append(
                Utterance(
                    role="host",
                    text=f"ポイントは、{takeaway}",
                    pause_after_ms=700,
                )
            )

    utterances.append(
        Utterance(
            role="host",
            text=(
                "以上、今日のトピックでした。"
                "リンクは番組ノートに載せています。明日もお楽しみに。"
            ),
            pause_after_ms=200,
        )
    )

    return [u.as_dict() for u in utterances]


def transcript_text(script: list[dict[str, Any]]) -> str:
    """Plain-text transcript for the RSS <itunes:transcript>/podcast:transcript."""
    return "\n\n".join((u.get("text") or "").strip() for u in script if u.get("text"))


def _label_source(source: str) -> str:
    return {
        "hackernews": "Hacker News",
        "bluesky": "Bluesky",
        "hatena": "はてなブックマーク",
        "reddit": "Reddit",
    }.get(source, source or "不明")
