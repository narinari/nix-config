"""Unit tests for topics.toml load + append round-trip."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import src.config as cfg  # noqa: E402


def test_load_topics_missing_file(tmp_path, monkeypatch):
    monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
    assert cfg.load_topics() == []


def test_append_topic_round_trip(tmp_path, monkeypatch):
    monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
    cfg.append_topic_to_toml(
        {
            "slug": "hobby-models",
            "title": "ホビー模型 Tips",
            "description": "テスト",
            "voicevox_speaker_id": 2,
            "target_segment_count": 5,
            "sources": [
                {"type": "hackernews", "query": "gunpla OR plamo"},
                {"type": "hatena", "category": "entertainment"},
            ],
        }
    )
    topics = cfg.load_topics()
    assert len(topics) == 1
    t = topics[0]
    assert t.slug == "hobby-models"
    assert t.title == "ホビー模型 Tips"
    assert t.voicevox_speaker_id == 2
    assert t.target_segment_count == 5
    assert [s.type for s in t.sources] == ["hackernews", "hatena"]
    assert t.sources[0].extra.get("query") == "gunpla OR plamo"


def test_append_two_topics(tmp_path, monkeypatch):
    monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
    cfg.append_topic_to_toml(
        {
            "slug": "one",
            "title": "One",
            "description": "x",
            "sources": [{"type": "hackernews", "query": "a"}],
        }
    )
    cfg.append_topic_to_toml(
        {
            "slug": "two",
            "title": "Two",
            "description": "y",
            "sources": [{"type": "reddit", "subreddit": "Gunpla"}],
        }
    )
    topics = cfg.load_topics()
    assert [t.slug for t in topics] == ["one", "two"]
