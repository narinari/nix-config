"""SQLite-backed state: episodes registry and dedup cache.

Schema:

    CREATE TABLE episodes (
        id TEXT PRIMARY KEY,         -- "<topic>:<yyyy-mm-dd>"
        topic TEXT NOT NULL,
        episode_date TEXT NOT NULL,  -- YYYY-MM-DD
        title TEXT NOT NULL,
        audio_path TEXT NOT NULL,    -- absolute path on disk
        audio_url TEXT NOT NULL,     -- public URL (RSS enclosure)
        duration_seconds INTEGER,
        size_bytes INTEGER,
        summary TEXT,
        script TEXT,                 -- JSON: full script
        created_at TEXT NOT NULL     -- ISO 8601
    );

    CREATE TABLE sources_seen (
        topic TEXT NOT NULL,
        normalized_url TEXT NOT NULL,
        title TEXT NOT NULL,
        first_seen_at TEXT NOT NULL,
        last_seen_at TEXT,           -- 最後にエピソード採用された時刻
        PRIMARY KEY (topic, normalized_url)
    );

`sources_seen` is the adoption history: a row exists only for articles that
made it into an episode. `adopted_urls` uses the full table (permanent URL
dedup); `recent_seen` windows on last_seen_at (fuzzy-title dedup).
"""

from __future__ import annotations

import json
import logging
import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator

from . import config as cfg

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class EpisodeRow:
    id: str
    topic: str
    episode_date: str
    title: str
    audio_path: str
    audio_url: str
    duration_seconds: int | None
    size_bytes: int | None
    summary: str | None
    script: dict[str, Any] | None
    created_at: str


def _connect() -> sqlite3.Connection:
    path = cfg.state_db_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


@contextmanager
def transaction() -> Iterator[sqlite3.Connection]:
    conn = _connect()
    try:
        _ensure_schema(conn)
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _ensure_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS episodes (
            id TEXT PRIMARY KEY,
            topic TEXT NOT NULL,
            episode_date TEXT NOT NULL,
            title TEXT NOT NULL,
            audio_path TEXT NOT NULL,
            audio_url TEXT NOT NULL,
            duration_seconds INTEGER,
            size_bytes INTEGER,
            summary TEXT,
            script TEXT,
            created_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_episodes_topic_date
            ON episodes(topic, episode_date DESC);

        CREATE TABLE IF NOT EXISTS sources_seen (
            topic TEXT NOT NULL,
            normalized_url TEXT NOT NULL,
            title TEXT NOT NULL,
            first_seen_at TEXT NOT NULL,
            last_seen_at TEXT,
            PRIMARY KEY (topic, normalized_url)
        );
        """
    )
    # Migration for DBs created before last_seen_at existed. Runs on every
    # connection but the PRAGMA check keeps it idempotent and cheap.
    cols = {row[1] for row in conn.execute("PRAGMA table_info(sources_seen)")}
    if "last_seen_at" not in cols:
        conn.execute("ALTER TABLE sources_seen ADD COLUMN last_seen_at TEXT")
        conn.execute("UPDATE sources_seen SET last_seen_at = first_seen_at")


def upsert_episode(row: EpisodeRow) -> None:
    with transaction() as conn:
        conn.execute(
            """
            INSERT INTO episodes (id, topic, episode_date, title, audio_path,
                audio_url, duration_seconds, size_bytes, summary, script,
                created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title=excluded.title,
                audio_path=excluded.audio_path,
                audio_url=excluded.audio_url,
                duration_seconds=excluded.duration_seconds,
                size_bytes=excluded.size_bytes,
                summary=excluded.summary,
                script=excluded.script,
                created_at=excluded.created_at
            """,
            (
                row.id,
                row.topic,
                row.episode_date,
                row.title,
                row.audio_path,
                row.audio_url,
                row.duration_seconds,
                row.size_bytes,
                row.summary,
                json.dumps(row.script, ensure_ascii=False) if row.script else None,
                row.created_at,
            ),
        )


def list_episodes(topic: str, limit: int = 10) -> list[EpisodeRow]:
    with transaction() as conn:
        rows = conn.execute(
            """
            SELECT * FROM episodes
            WHERE topic = ?
            ORDER BY episode_date DESC
            LIMIT ?
            """,
            (topic, limit),
        ).fetchall()
    return [_row_to_episode(r) for r in rows]


def get_episode(episode_id: str) -> EpisodeRow | None:
    with transaction() as conn:
        row = conn.execute(
            "SELECT * FROM episodes WHERE id = ?", (episode_id,)
        ).fetchone()
    return _row_to_episode(row) if row else None


def _row_to_episode(r: sqlite3.Row) -> EpisodeRow:
    script_json = r["script"]
    script = json.loads(script_json) if script_json else None
    return EpisodeRow(
        id=r["id"],
        topic=r["topic"],
        episode_date=r["episode_date"],
        title=r["title"],
        audio_path=r["audio_path"],
        audio_url=r["audio_url"],
        duration_seconds=r["duration_seconds"],
        size_bytes=r["size_bytes"],
        summary=r["summary"],
        script=script,
        created_at=r["created_at"],
    )


def remember_sources(topic: str, items: list[tuple[str, str]]) -> None:
    """Record (normalized_url, title) pairs as adopted for this topic.

    Re-adoption bumps last_seen_at so the recent_seen window re-extends
    (with INSERT OR IGNORE the timestamp froze at first adoption and the
    window silently expired — the "same episode forever" bug).
    """
    if not items:
        return
    now = datetime.now(timezone.utc).isoformat()
    with transaction() as conn:
        conn.executemany(
            """
            INSERT INTO sources_seen
                (topic, normalized_url, title, first_seen_at, last_seen_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(topic, normalized_url) DO UPDATE SET
                last_seen_at = excluded.last_seen_at,
                title = excluded.title
            """,
            [(topic, url, title, now, now) for url, title in items],
        )


def recent_seen(topic: str, days: int = 14) -> list[tuple[str, str]]:
    """Return (normalized_url, title) adopted within the last `days`."""
    from datetime import timedelta

    cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
    with transaction() as conn:
        rows = conn.execute(
            """
            SELECT normalized_url, title FROM sources_seen
            WHERE topic = ? AND COALESCE(last_seen_at, first_seen_at) >= ?
            """,
            (topic, cutoff),
        ).fetchall()
    return [(r["normalized_url"], r["title"]) for r in rows]


def adopted_urls(topic: str) -> set[str]:
    """All normalized URLs ever adopted into an episode for this topic.

    Used for permanent URL-exact dedup: re-running the same article is always
    wrong no matter how long ago it aired. Fuzzy-title dedup stays windowed
    (recent_seen) so recurring series titles aren't over-matched.
    """
    with transaction() as conn:
        rows = conn.execute(
            "SELECT normalized_url FROM sources_seen WHERE topic = ?",
            (topic,),
        ).fetchall()
    return {r["normalized_url"] for r in rows}
