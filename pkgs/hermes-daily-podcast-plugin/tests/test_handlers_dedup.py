"""Thin integration tests for generate_daily_episode's dedup stage.

sources / score are monkeypatched; state runs for real against a tmp dir.
Each test stops the pipeline at scoring (all candidates scored LOW → early
return) so no summarize / VOICEVOX code is reached.
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import src.config as cfg  # noqa: E402
import src.handlers as handlers  # noqa: E402
import src.state as state_mod  # noqa: E402


TOPIC = cfg.TopicConfig.from_dict(
    {
        "slug": "hobby-models",
        "title": "ホビー模型 Tips",
        "description": "プラモデル",
        "sources": [{"type": "hatena", "tags": ["模型"]}],
    }
)


def _run_with_candidates(
    monkeypatch, candidates: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """Run generate_daily_episode far enough to capture what reaches scoring."""
    reached: list[dict[str, Any]] = []

    def fake_score(cands, **kwargs):
        reached.extend(cands)
        return [{**c, "score": 1.0, "score_reason": "LOW"} for c in cands]

    monkeypatch.setattr(handlers.cfg, "find_topic", lambda slug: TOPIC)
    monkeypatch.setattr(handlers.sources_mod, "fetch_all", lambda *a, **kw: candidates)
    monkeypatch.setattr(handlers.score_mod, "score_candidates", fake_score)
    result = handlers.generate_daily_episode(topic_slug="hobby-models")
    assert "error" in result  # all LOW → early return before summarize
    return reached


class TestScoreUnavailable:
    def test_score_unavailable_returns_error_envelope(self, tmp_path, monkeypatch):
        """採点 LLM が死んでいる夜はクラッシュでも配信でもなく error を返す。"""
        import src.score as score_mod

        monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
        monkeypatch.setattr(handlers.cfg, "find_topic", lambda slug: TOPIC)
        monkeypatch.setattr(
            handlers.sources_mod,
            "fetch_all",
            lambda *a, **kw: [{"title": "x", "url": "https://example.com/x"}],
        )

        def raise_unavailable(cands, **kwargs):
            raise score_mod.ScoreUnavailableError("LLM timed out")

        monkeypatch.setattr(
            handlers.score_mod, "score_candidates", raise_unavailable
        )
        result = handlers.generate_daily_episode(topic_slug="hobby-models")
        assert "error" in result
        assert "scoring" in result["error"]


class TestTwoStageDedup:
    def test_adopted_url_is_permanently_excluded(self, tmp_path, monkeypatch):
        """Adopted long ago (beyond the 14-day window) → still excluded."""
        monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
        state_mod.remember_sources(
            "hobby-models", [("https://nippper.com/2025/11/125062", "レトロフォーミュラ")]
        )
        with state_mod.transaction() as conn:
            conn.execute(
                "UPDATE sources_seen SET first_seen_at = '2026-01-01T00:00:00+00:00',"
                " last_seen_at = '2026-01-01T00:00:00+00:00'"
            )

        reached = _run_with_candidates(
            monkeypatch,
            [
                {"title": "レトロフォーミュラ", "url": "https://nippper.com/2025/11/125062"},
                {"title": "新作キットレビュー", "url": "https://example.com/new"},
            ],
        )
        assert [c["url"] for c in reached] == ["https://example.com/new"]

    def test_similar_title_within_window_is_excluded(self, tmp_path, monkeypatch):
        monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
        state_mod.remember_sources(
            "hobby-models", [("https://example.com/a", "ガンプラ塗装の極意まとめ")]
        )
        reached = _run_with_candidates(
            monkeypatch,
            [
                # 別 URL だがほぼ同一タイトル → fuzzy 一致で除外されるべき
                {"title": "ガンプラ塗装の極意まとめ", "url": "https://mirror.example.com/a"},
                {"title": "ジオラマ素材の選び方", "url": "https://example.com/b"},
            ],
        )
        assert [c["url"] for c in reached] == ["https://example.com/b"]

    def test_fresh_candidates_pass_through(self, tmp_path, monkeypatch):
        monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
        reached = _run_with_candidates(
            monkeypatch,
            [{"title": "新製品情報", "url": "https://example.com/n"}],
        )
        assert [c["url"] for c in reached] == ["https://example.com/n"]
