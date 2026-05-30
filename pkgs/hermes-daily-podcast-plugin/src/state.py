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
        PRIMARY KEY (topic, normalized_url)
    );
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
            PRIMARY KEY (topic, normalized_url)
        );
        """
    )


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
    """Record (normalized_url, title) pairs as seen for this topic."""
    if not items:
        return
    now = datetime.now(timezone.utc).isoformat()
    with transaction() as conn:
        conn.executemany(
            """
            INSERT OR IGNORE INTO sources_seen
                (topic, normalized_url, title, first_seen_at)
            VALUES (?, ?, ?, ?)
            """,
            [(topic, url, title, now) for url, title in items],
        )


def recent_seen(topic: str, days: int = 14) -> list[tuple[str, str]]:
    """Return (normalized_url, title) seen within the last `days` for topic."""
    from datetime import timedelta

    cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
    with transaction() as conn:
        rows = conn.execute(
            """
            SELECT normalized_url, title FROM sources_seen
            WHERE topic = ? AND first_seen_at >= ?
            """,
            (topic, cutoff),
        ).fetchall()
    return [(r["normalized_url"], r["title"]) for r in rows]
