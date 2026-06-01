"""Unit tests for HIGH/MID/LOW label scoring.

We patch the LLM layer so the tests stay hermetic — no aperture round-trip.
The interesting behaviors are: label-to-score mapping, missing-id resilience,
legacy float-score backward compatibility, and the MIN_SELECTION_SCORE floor.
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import src.config as cfg  # noqa: E402
import src.score as score_mod  # noqa: E402


def _topic() -> cfg.TopicConfig:
    return cfg.TopicConfig.from_dict(
        {
            "slug": "hobby-models",
            "title": "ホビー模型 Tips",
            "description": "プラモデル・フィギュア・ジオラマ",
            "sources": [{"type": "hackernews", "query": "gunpla"}],
        }
    )


def _candidates(n: int) -> list[dict[str, Any]]:
    return [
        {
            "title": f"item {i}",
            "url": f"https://example.com/{i}",
            "source": "hackernews",
            "points": 10,
        }
        for i in range(n)
    ]


def _stub_llm(reply: dict[str, Any], *, captured: dict[str, Any] | None = None):
    """Build a llm.chat_json replacement that returns `reply`.

    If `captured` is provided we stash the model kwarg so tests can assert
    the lightweight model was actually used.
    """

    def fake(messages, **kwargs):
        if captured is not None:
            captured["model"] = kwargs.get("model")
            captured["messages"] = messages
        return reply

    return fake


class TestLabelMapping:
    def test_high_mid_low_map_to_known_floats(self, monkeypatch):
        monkeypatch.setattr(
            score_mod.llm,
            "chat_json",
            _stub_llm(
                {
                    "scores": [
                        {"id": 0, "label": "HIGH", "reason": "ジャンル一致・新規性"},
                        {"id": 1, "label": "MID", "reason": "ジャンル一致だが浅い"},
                        {"id": 2, "label": "LOW", "reason": "ジャンル外"},
                    ]
                },
            ),
        )
        result = score_mod.score_candidates(_candidates(3), topic=_topic())
        assert [c["score"] for c in result] == [10.0, 5.0, 1.0]
        assert result[0]["score_reason"].startswith("ジャンル一致")

    def test_uses_lightweight_score_model(self, monkeypatch):
        """The score pass must hit cfg.score_model() (cheap model), not the
        summarization model — that's the whole point of Phase 1.5."""
        monkeypatch.setenv("HERMES_DAILY_PODCAST_SCORE_MODEL", "tiny:4b")
        monkeypatch.setenv("HERMES_DAILY_PODCAST_SUMMARIZE_MODEL", "heavy:35b")
        captured: dict[str, Any] = {}
        monkeypatch.setattr(
            score_mod.llm,
            "chat_json",
            _stub_llm(
                {"scores": [{"id": 0, "label": "HIGH", "reason": "x"}]},
                captured=captured,
            ),
        )
        score_mod.score_candidates(_candidates(1), topic=_topic())
        assert captured["model"] == "tiny:4b"

    def test_lowercase_label_is_normalized(self, monkeypatch):
        monkeypatch.setattr(
            score_mod.llm,
            "chat_json",
            _stub_llm(
                {"scores": [{"id": 0, "label": "high", "reason": "ok"}]}
            ),
        )
        result = score_mod.score_candidates(_candidates(1), topic=_topic())
        assert result[0]["score"] == 10.0

    def test_unknown_label_falls_to_zero(self, monkeypatch):
        monkeypatch.setattr(
            score_mod.llm,
            "chat_json",
            _stub_llm(
                {"scores": [{"id": 0, "label": "MAYBE", "reason": "?"}]}
            ),
        )
        result = score_mod.score_candidates(_candidates(1), topic=_topic())
        assert result[0]["score"] == 0.0

    def test_missing_ids_keep_zero(self, monkeypatch):
        monkeypatch.setattr(
            score_mod.llm,
            "chat_json",
            _stub_llm(
                {"scores": [{"id": 1, "label": "HIGH", "reason": "x"}]}
            ),
        )
        result = score_mod.score_candidates(_candidates(3), topic=_topic())
        assert result[0]["score"] == 0.0
        assert result[1]["score"] == 10.0
        assert result[2]["score"] == 0.0


class TestLegacyFloatCompat:
    """Old prompts (or a model that ignores the new instruction) may still emit
    a `score` float. Accept it so a partial rollout doesn't zero everything."""

    def test_legacy_float_score_is_accepted(self, monkeypatch):
        monkeypatch.setattr(
            score_mod.llm,
            "chat_json",
            _stub_llm(
                {"scores": [{"id": 0, "score": 7.5, "reason": "legacy"}]}
            ),
        )
        result = score_mod.score_candidates(_candidates(1), topic=_topic())
        assert result[0]["score"] == 7.5


class TestSelectTopFloor:
    def test_low_label_is_filtered_by_floor(self):
        scored = [
            {"title": "off-topic", "score": 1.0},  # LOW
            {"title": "decent", "score": 5.0},  # MID
            {"title": "great", "score": 10.0},  # HIGH
        ]
        picked = score_mod.select_top(scored, target=5)
        assert [c["title"] for c in picked] == ["great", "decent"]

    def test_all_low_returns_empty(self):
        scored = [{"title": "x", "score": 1.0}, {"title": "y", "score": 1.0}]
        assert score_mod.select_top(scored, target=3) == []
