"""Smoke test for the script composer."""

from __future__ import annotations

import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import src.config as cfg  # noqa: E402
import src.script as script_mod  # noqa: E402


def _topic() -> cfg.TopicConfig:
    return cfg.TopicConfig.from_dict(
        {
            "slug": "hobby-models",
            "title": "ホビー模型 Tips",
            "description": "テスト",
            "sources": [{"type": "hackernews", "query": "gunpla"}],
        }
    )


def test_script_has_intro_and_outro():
    topic = _topic()
    items = [
        {
            "title": "Bandai launches HG Aerial Rebuild",
            "source": "reddit",
            "summary_ja": "バンダイから新しい HG が発表されました。",
            "takeaway_ja": "予約は明日 10 時開始です。",
        },
    ]
    s = script_mod.compose_script(topic, date(2026, 5, 30), items)
    assert s[0]["role"] == "host"
    assert "2026年5月30日" in s[0]["text"]
    assert any("以上" in u["text"] for u in s)
    transcript = script_mod.transcript_text(s)
    assert "バンダイ" in transcript
    assert "予約は明日" in transcript
