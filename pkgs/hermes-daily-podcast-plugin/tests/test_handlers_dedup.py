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


class TestSinceInjection:
    """handlers は「前回生成日 − 2 日」を since_date として全 source に注入
    する (hatena が date_begin に使う)。重複取得は dedup が吸収する。"""

    def _capture_sources(self, monkeypatch) -> list[Any]:
        captured: list[Any] = []

        def fake_fetch_all(sources, *a, **kw):
            captured.extend(sources)
            return []  # "no candidates" で早期 return させる

        monkeypatch.setattr(handlers.cfg, "find_topic", lambda slug: TOPIC)
        monkeypatch.setattr(handlers.sources_mod, "fetch_all", fake_fetch_all)
        return captured

    def test_since_is_last_episode_minus_overlap(self, tmp_path, monkeypatch):
        monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
        state_mod.upsert_episode(
            state_mod.EpisodeRow(
                id="hobby-models:2026-09-01",
                topic="hobby-models",
                episode_date="2026-09-01",
                title="t",
                audio_path="/x.mp3",
                audio_url="http://x/x.mp3",
                duration_seconds=1,
                size_bytes=1,
                summary=None,
                script=None,
                created_at="2026-09-01T00:00:00+00:00",
            )
        )
        captured = self._capture_sources(monkeypatch)
        handlers.generate_daily_episode(
            topic_slug="hobby-models", target_date="2026-09-07"
        )
        assert captured[0].extra["since_date"] == "2026-08-30"

    def test_since_defaults_to_30_days_without_history(self, tmp_path, monkeypatch):
        monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
        captured = self._capture_sources(monkeypatch)
        handlers.generate_daily_episode(
            topic_slug="hobby-models", target_date="2026-09-07"
        )
        assert captured[0].extra["since_date"] == "2026-08-08"

    def test_since_is_clamped_to_60_days(self, tmp_path, monkeypatch):
        monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
        state_mod.upsert_episode(
            state_mod.EpisodeRow(
                id="hobby-models:2026-01-01",
                topic="hobby-models",
                episode_date="2026-01-01",
                title="t",
                audio_path="/x.mp3",
                audio_url="http://x/x.mp3",
                duration_seconds=1,
                size_bytes=1,
                summary=None,
                script=None,
                created_at="2026-01-01T00:00:00+00:00",
            )
        )
        captured = self._capture_sources(monkeypatch)
        handlers.generate_daily_episode(
            topic_slug="hobby-models", target_date="2026-09-07"
        )
        assert captured[0].extra["since_date"] == "2026-07-09"

    def test_explicit_source_config_is_not_overwritten(self, tmp_path, monkeypatch):
        monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
        captured = self._capture_sources(monkeypatch)
        handlers.generate_daily_episode(
            topic_slug="hobby-models", target_date="2026-09-07"
        )
        # 元 TopicConfig の extra (tags) は保持される
        assert captured[0].extra["tags"] == ["模型"]
        assert captured[0].type == "hatena"


def _episode_row(episode_date: str, items: list[dict[str, Any]] | None = None):
    return state_mod.EpisodeRow(
        id=f"hobby-models:{episode_date}",
        topic="hobby-models",
        episode_date=episode_date,
        title="t",
        audio_path="/x.mp3",
        audio_url="http://x/x.mp3",
        duration_seconds=1,
        size_bytes=1,
        summary=None,
        script={"utterances": [], "items": items} if items is not None else None,
        created_at=f"{episode_date}T00:00:00+00:00",
    )


class TestSinceIgnoresNewerEpisodes:
    """regenerate_episode で過去日を再生成するとき、target より後の
    エピソードを since の基準にしてはいけない (since が target を追い越し
    hatena がほぼ空になる)。"""

    def test_since_uses_latest_episode_before_target(self, tmp_path, monkeypatch):
        monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
        state_mod.upsert_episode(_episode_row("2026-08-20"))
        state_mod.upsert_episode(_episode_row("2026-09-07"))  # target より後

        captured: list[Any] = []

        def fake_fetch_all(sources, *a, **kw):
            captured.extend(sources)
            return []

        monkeypatch.setattr(handlers.cfg, "find_topic", lambda slug: TOPIC)
        monkeypatch.setattr(handlers.sources_mod, "fetch_all", fake_fetch_all)
        handlers.generate_daily_episode(
            topic_slug="hobby-models", target_date="2026-09-01"
        )
        # 2026-09-07 ではなく 2026-08-20 を基準に (− 2 日)
        assert captured[0].extra["since_date"] == "2026-08-18"

    def test_regenerating_the_only_episode_falls_back_to_default(
        self, tmp_path, monkeypatch
    ):
        monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
        state_mod.upsert_episode(_episode_row("2026-09-01"))

        captured: list[Any] = []

        def fake_fetch_all(sources, *a, **kw):
            captured.extend(sources)
            return []

        monkeypatch.setattr(handlers.cfg, "find_topic", lambda slug: TOPIC)
        monkeypatch.setattr(handlers.sources_mod, "fetch_all", fake_fetch_all)
        handlers.generate_daily_episode(
            topic_slug="hobby-models", target_date="2026-09-01"
        )
        # 自分自身 (同日) は基準にしない → 履歴なし扱いで 30 日前
        assert captured[0].extra["since_date"] == "2026-08-02"


class TestRegenerateAllowsOwnArticles:
    def test_own_episode_urls_are_not_excluded(self, tmp_path, monkeypatch):
        """同一日の再生成では、そのエピソード自身が使った記事は候補に残す
        (恒久 dedup は「別の日の再放送」を防ぐためのもの)。"""
        monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
        state_mod.upsert_episode(
            _episode_row(
                "2026-09-01",
                items=[{"url": "https://example.com/mine", "title": "自分の記事"}],
            )
        )
        state_mod.remember_sources(
            "hobby-models",
            [
                ("https://example.com/mine", "自分の記事"),
                ("https://example.com/other", "別の日の記事"),
            ],
        )

        reached: list[dict[str, Any]] = []

        def fake_score(cands, **kwargs):
            reached.extend(cands)
            return [{**c, "score": 1.0, "score_reason": "LOW"} for c in cands]

        monkeypatch.setattr(handlers.cfg, "find_topic", lambda slug: TOPIC)
        monkeypatch.setattr(
            handlers.sources_mod,
            "fetch_all",
            lambda *a, **kw: [
                {"title": "自分の記事", "url": "https://example.com/mine"},
                {"title": "別の日の記事", "url": "https://example.com/other"},
            ],
        )
        monkeypatch.setattr(handlers.score_mod, "score_candidates", fake_score)
        handlers.generate_daily_episode(
            topic_slug="hobby-models", target_date="2026-09-01"
        )
        assert [c["url"] for c in reached] == ["https://example.com/mine"]


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
