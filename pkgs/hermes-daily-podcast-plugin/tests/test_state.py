"""Round-trip tests for the sources_seen history (dedup state).

These exist because of a production bug: `remember_sources` used
`INSERT OR IGNORE`, so `first_seen_at` never advanced and any article older
than the 14-day `recent_seen` window was re-adopted forever — the same 4
articles headlined 8 consecutive episodes.
"""

from __future__ import annotations

import sqlite3
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import src.state as state_mod  # noqa: E402


def _iso_days_ago(days: int) -> str:
    return (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()


class TestRememberRecentRoundtrip:
    def test_remembered_source_is_recent(self, tmp_path, monkeypatch):
        monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
        state_mod.remember_sources("t", [("https://example.com/a", "記事A")])
        assert state_mod.recent_seen("t", days=14) == [
            ("https://example.com/a", "記事A")
        ]

    def test_topics_are_isolated(self, tmp_path, monkeypatch):
        monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
        state_mod.remember_sources("t1", [("https://example.com/a", "A")])
        assert state_mod.recent_seen("t2", days=14) == []


class TestLastSeenBump:
    def test_re_remember_bumps_last_seen_at(self, tmp_path, monkeypatch):
        """An article re-adopted after falling out of the window must re-enter
        the window (the INSERT OR IGNORE bug kept it out forever)."""
        monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
        state_mod.remember_sources("t", [("https://example.com/a", "A")])
        # Simulate the first adoption having happened 100 days ago.
        with state_mod.transaction() as conn:
            conn.execute(
                "UPDATE sources_seen SET first_seen_at = ?, last_seen_at = ?",
                (_iso_days_ago(100), _iso_days_ago(100)),
            )
        assert state_mod.recent_seen("t", days=14) == []

        state_mod.remember_sources("t", [("https://example.com/a", "A")])
        assert state_mod.recent_seen("t", days=14) == [
            ("https://example.com/a", "A")
        ]

    def test_first_seen_at_is_preserved(self, tmp_path, monkeypatch):
        monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
        state_mod.remember_sources("t", [("https://example.com/a", "A")])
        with state_mod.transaction() as conn:
            conn.execute(
                "UPDATE sources_seen SET first_seen_at = ?", (_iso_days_ago(100),)
            )
        state_mod.remember_sources("t", [("https://example.com/a", "A")])
        with state_mod.transaction() as conn:
            row = conn.execute(
                "SELECT first_seen_at, last_seen_at FROM sources_seen"
            ).fetchone()
        assert row["first_seen_at"] < _iso_days_ago(99)
        assert row["last_seen_at"] > _iso_days_ago(1)


class TestLegacySchemaMigration:
    def _make_legacy_db(self, tmp_path: Path) -> None:
        """Hand-build the pre-last_seen_at schema with one old row."""
        conn = sqlite3.connect(tmp_path / "state.sqlite")
        conn.executescript(
            """
            CREATE TABLE sources_seen (
                topic TEXT NOT NULL,
                normalized_url TEXT NOT NULL,
                title TEXT NOT NULL,
                first_seen_at TEXT NOT NULL,
                PRIMARY KEY (topic, normalized_url)
            );
            """
        )
        conn.execute(
            "INSERT INTO sources_seen VALUES (?, ?, ?, ?)",
            ("t", "https://example.com/old", "旧記事", _iso_days_ago(3)),
        )
        conn.commit()
        conn.close()

    def test_migration_backfills_last_seen_at(self, tmp_path, monkeypatch):
        monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
        self._make_legacy_db(tmp_path)
        # Any state access must upgrade the schema without crashing.
        assert state_mod.recent_seen("t", days=14) == [
            ("https://example.com/old", "旧記事")
        ]
        with state_mod.transaction() as conn:
            row = conn.execute(
                "SELECT first_seen_at, last_seen_at FROM sources_seen"
            ).fetchone()
        assert row["last_seen_at"] == row["first_seen_at"]

    def test_remember_works_on_migrated_db(self, tmp_path, monkeypatch):
        monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
        self._make_legacy_db(tmp_path)
        state_mod.remember_sources("t", [("https://example.com/old", "旧記事")])
        assert state_mod.recent_seen("t", days=14) == [
            ("https://example.com/old", "旧記事")
        ]


class TestAdoptedUrls:
    def test_includes_urls_beyond_recent_window(self, tmp_path, monkeypatch):
        """Permanent dedup: an adopted URL never leaves adopted_urls even when
        it has aged out of the fuzzy-title window."""
        monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
        state_mod.remember_sources("t", [("https://example.com/a", "A")])
        with state_mod.transaction() as conn:
            conn.execute(
                "UPDATE sources_seen SET first_seen_at = ?, last_seen_at = ?",
                (_iso_days_ago(100), _iso_days_ago(100)),
            )
        assert state_mod.recent_seen("t", days=14) == []
        assert state_mod.adopted_urls("t") == {"https://example.com/a"}

    def test_empty_for_unknown_topic(self, tmp_path, monkeypatch):
        monkeypatch.setenv("DAILY_PODCAST_STATE_DIR", str(tmp_path))
        assert state_mod.adopted_urls("nope") == set()
