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
            captured["timeout"] = kwargs.get("timeout")
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

    def test_uses_extended_score_timeout(self, monkeypatch):
        """27B 一括採点は実測 ~260s — llm.py デフォルト 300s では夜間の
        揺らぎに耐えないため、採点専用の延長タイムアウトを渡す。"""
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
        assert captured["timeout"] == score_mod.SCORE_TIMEOUT_SECONDS

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


class TestFailClosed:
    """LLM 採点が使えない夜は「間違ったエピソード」より「エピソードなし」。
    生成された全 23 エピソードが popularity フォールバック産 (ジャンル外
    記事入り) だった事故の再発防止。"""

    def _raise_llm_error(self, monkeypatch):
        def fake(messages, **kwargs):
            raise score_mod.llm.LlmError("timed out")

        monkeypatch.setattr(score_mod.llm, "chat_json", fake)

    def test_llm_error_raises_score_unavailable_by_default(self, monkeypatch):
        monkeypatch.delenv("DAILY_PODCAST_ALLOW_POPULARITY_FALLBACK", raising=False)
        self._raise_llm_error(monkeypatch)
        try:
            score_mod.score_candidates(_candidates(2), topic=_topic())
        except score_mod.ScoreUnavailableError:
            pass
        else:
            raise AssertionError("expected ScoreUnavailableError")

    def test_bad_shape_raises_score_unavailable_by_default(self, monkeypatch):
        monkeypatch.delenv("DAILY_PODCAST_ALLOW_POPULARITY_FALLBACK", raising=False)
        monkeypatch.setattr(
            score_mod.llm, "chat_json", _stub_llm({"nonsense": True})
        )
        try:
            score_mod.score_candidates(_candidates(2), topic=_topic())
        except score_mod.ScoreUnavailableError:
            pass
        else:
            raise AssertionError("expected ScoreUnavailableError")

    def test_env_optin_restores_popularity_fallback(self, monkeypatch):
        monkeypatch.setenv("DAILY_PODCAST_ALLOW_POPULARITY_FALLBACK", "1")
        self._raise_llm_error(monkeypatch)
        result = score_mod.score_candidates(_candidates(2), topic=_topic())
        assert len(result) == 2
        assert all("fallback" in c["score_reason"] for c in result)


class TestFallbackFreshnessDecay:
    """opt-in フォールバックでもブクマ数単調増加による「古い人気記事が恒久
    上位」は防ぐ: 7 日超で半減、14 日超で 0。"""

    def _aged(self, days_ago: int, points: int = 500) -> list[dict[str, Any]]:
        from datetime import datetime, timedelta, timezone

        ts = (
            datetime.now(timezone.utc) - timedelta(days=days_ago)
        ).isoformat()
        return [
            {
                "title": "x",
                "url": "https://example.com/x",
                "points": points,
                "published_at": ts,
            }
        ]

    def test_stale_candidate_scores_zero(self):
        result = score_mod._fallback_score(self._aged(30))
        assert result[0]["score"] == 0.0

    def test_week_old_candidate_is_halved(self):
        fresh = score_mod._fallback_score(self._aged(1))[0]["score"]
        aged = score_mod._fallback_score(self._aged(10))[0]["score"]
        assert aged == fresh / 2

    def test_missing_published_at_is_not_penalized(self):
        result = score_mod._fallback_score(
            [{"title": "x", "url": "https://example.com/x", "points": 500}]
        )
        assert result[0]["score"] == 10.0


class TestScoringCostControl:
    """27B の decode は実測 ~7 tok/s — 全候補に reason を書かせると
    600s を超える。LOW は reason 省略、候補は新しい順に最大 50 件。"""

    def _stub(self, monkeypatch) -> dict[str, Any]:
        captured: dict[str, Any] = {}
        monkeypatch.setattr(
            score_mod.llm,
            "chat_json",
            _stub_llm({"scores": []}, captured=captured),
        )
        return captured

    def test_prompt_tells_low_to_omit_reason(self, monkeypatch):
        captured = self._stub(monkeypatch)
        score_mod.score_candidates(_candidates(1), topic=_topic())
        user_msg = captured["messages"][-1]["content"]
        assert "LOW" in user_msg and "reason" in user_msg
        assert "空" in user_msg  # 「LOW の reason は空でよい」指示

    def test_caps_prompt_candidates_but_returns_all(self, monkeypatch):
        captured = self._stub(monkeypatch)
        result = score_mod.score_candidates(_candidates(60), topic=_topic())
        user_msg = captured["messages"][-1]["content"]
        assert user_msg.count("id=") == score_mod.MAX_SCORING_CANDIDATES
        assert len(result) == 60  # 溢れた候補も score 0 で返る

    def test_cap_keeps_newest_candidates(self, monkeypatch):
        from datetime import datetime, timedelta, timezone

        captured = self._stub(monkeypatch)
        now = datetime.now(timezone.utc)
        cands = []
        for i in range(60):
            cands.append(
                {
                    "title": f"item {i}",
                    "url": f"https://example.com/{i}",
                    # i が大きいほど新しい
                    "published_at": (now - timedelta(days=60 - i)).isoformat(),
                }
            )
        score_mod.score_candidates(cands, topic=_topic())
        user_msg = captured["messages"][-1]["content"]
        # 最も古い 10 件 (i=0..9) が落ち、新しい候補は残る
        assert "https://example.com/0\n" not in user_msg
        assert "https://example.com/59" in user_msg


class TestRecentTitlesInPrompt:
    def test_prompt_includes_recent_titles(self, monkeypatch):
        captured: dict[str, Any] = {}
        monkeypatch.setattr(
            score_mod.llm,
            "chat_json",
            _stub_llm(
                {"scores": [{"id": 0, "label": "HIGH", "reason": "x"}]},
                captured=captured,
            ),
        )
        score_mod.score_candidates(
            _candidates(1),
            topic=_topic(),
            recent_titles=["既出のレビュー記事タイトル"],
        )
        user_msg = captured["messages"][-1]["content"]
        assert "既出のレビュー記事タイトル" in user_msg

    def test_prompt_omits_section_when_no_titles(self, monkeypatch):
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
        user_msg = captured["messages"][-1]["content"]
        assert "既出タイトル" not in user_msg


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
