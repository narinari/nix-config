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


def test_score_model_default(monkeypatch):
    monkeypatch.delenv("HERMES_DAILY_PODCAST_SCORE_MODEL", raising=False)
    monkeypatch.delenv("HERMES_DAILY_PODCAST_LLM_MODEL", raising=False)
    assert cfg.score_model() == cfg.DEFAULT_SCORE_MODEL


def test_score_model_explicit_wins(monkeypatch):
    monkeypatch.setenv("HERMES_DAILY_PODCAST_SCORE_MODEL", "explicit:7b")
    monkeypatch.setenv("HERMES_DAILY_PODCAST_LLM_MODEL", "legacy:35b")
    assert cfg.score_model() == "explicit:7b"


def test_score_model_falls_back_to_legacy_llm_model(monkeypatch):
    monkeypatch.delenv("HERMES_DAILY_PODCAST_SCORE_MODEL", raising=False)
    monkeypatch.setenv("HERMES_DAILY_PODCAST_LLM_MODEL", "legacy:35b")
    assert cfg.score_model() == "legacy:35b"


def test_summarize_model_default(monkeypatch):
    monkeypatch.delenv("HERMES_DAILY_PODCAST_SUMMARIZE_MODEL", raising=False)
    monkeypatch.delenv("HERMES_DAILY_PODCAST_LLM_MODEL", raising=False)
    assert cfg.summarize_model() == cfg.DEFAULT_SUMMARIZE_MODEL


def test_summarize_model_explicit_wins(monkeypatch):
    monkeypatch.setenv("HERMES_DAILY_PODCAST_SUMMARIZE_MODEL", "explicit:70b")
    monkeypatch.setenv("HERMES_DAILY_PODCAST_LLM_MODEL", "legacy:35b")
    assert cfg.summarize_model() == "explicit:70b"


def test_llm_model_is_summarize_alias(monkeypatch):
    """Legacy entry point (`llm_model`) must equal summarize_model so older
    callers that read `cfg.llm_model()` still get the heavy model."""
    monkeypatch.setenv("HERMES_DAILY_PODCAST_SUMMARIZE_MODEL", "heavy:35b")
    monkeypatch.delenv("HERMES_DAILY_PODCAST_SCORE_MODEL", raising=False)
    assert cfg.llm_model() == "heavy:35b"


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
