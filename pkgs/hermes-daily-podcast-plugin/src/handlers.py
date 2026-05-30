"""Tool handlers.

These are the user-facing entry points called by Hermes when the LLM picks a
tool. Each handler is deterministic on success and returns a plain dict; the
__init__.py `_safe_handler` wraps them to JSON-encode and convert exceptions
to error envelopes.
"""

from __future__ import annotations

import logging
from datetime import date as date_cls
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

from . import config as cfg
from . import dedupe
from . import rss as rss_mod
from . import score as score_mod
from . import script as script_mod
from . import sources as sources_mod
from . import state as state_mod
from . import summarize as summ_mod
from . import voicevox

logger = logging.getLogger(__name__)


def generate_daily_episode(
    *,
    topic_slug: str,
    target_date: str | None = None,
    hint: str | None = None,
    # Hermes runtime injects metadata kwargs (task_id, etc) that aren't part of
    # the tool schema. Absorb them so the handler doesn't TypeError.
    **_: Any,
) -> dict[str, Any]:
    """End-to-end generation. Idempotent for the same (topic, date)."""
    topic = cfg.find_topic(topic_slug)
    if topic is None:
        return {
            "error": f"unknown topic: {topic_slug}",
            "hint": "list_topics で登録済みトピックを確認してください",
        }

    target = _resolve_target_date(target_date)

    raw_candidates = sources_mod.fetch_all(list(topic.sources))
    logger.info(
        "daily-podcast generate %s/%s: %d raw candidates",
        topic_slug, target, len(raw_candidates),
    )
    if not raw_candidates:
        return {
            "error": "no candidates returned from any source",
            "topic_slug": topic_slug,
            "target_date": target.isoformat(),
        }

    seen = state_mod.recent_seen(topic_slug, days=14)
    deduped: list[dict[str, Any]] = []
    for c in raw_candidates:
        if dedupe.is_duplicate(c.get("url") or "", c.get("title") or "", seen):
            continue
        deduped.append(c)
    logger.info("daily-podcast generate %s: %d after dedup", topic_slug, len(deduped))

    if not deduped:
        return {
            "error": "all candidates were duplicates of previously-seen items",
            "topic_slug": topic_slug,
            "target_date": target.isoformat(),
        }

    scored = score_mod.score_candidates(deduped, topic=topic, hint=hint)
    selected = score_mod.select_top(scored, topic.target_segment_count)
    if not selected:
        # All candidates were below the relevance floor — refusing to ship
        # an off-topic episode is better than shipping confidently wrong audio.
        return {
            "error": "no candidates passed the relevance threshold",
            "topic_slug": topic_slug,
            "target_date": target.isoformat(),
            "diagnostic": {
                "raw_candidates": len(raw_candidates),
                "after_dedup": len(deduped),
                "max_score": max((c.get("score") or 0 for c in scored), default=0),
                "hint": (
                    "topics.toml の source query が広すぎてジャンル外記事ばかりが集まっている、"
                    "または LLM 採点が失敗してフォールバックが効いた可能性。"
                    "journalctl -u hermes-agent | grep daily-podcast を確認。"
                ),
            },
        }
    summarized = summ_mod.summarize_each(selected, topic=topic, hint=hint)
    script_obj = script_mod.compose_script(topic, target, summarized)

    audio_dir = cfg.episodes_dir() / topic_slug
    audio_dir.mkdir(parents=True, exist_ok=True)
    mp3_path = audio_dir / f"{target.isoformat()}.mp3"
    synth_meta = voicevox.synthesize_script(
        script_obj,
        output_mp3=mp3_path,
        default_speaker_id=topic.voicevox_speaker_id,
    )

    transcript = script_mod.transcript_text(script_obj)
    rss_mod.write_transcript(topic_slug, target.isoformat(), transcript)

    audio_url = f"{cfg.public_base_url()}/{topic_slug}/{target.isoformat()}.mp3"
    title = f"{topic.title} {_japanese_date(target)} - {len(selected)}本"
    summary = "今日のラインナップ: " + " / ".join(
        (s.get("title") or "")[:60] for s in selected
    )
    episode_id = f"{topic_slug}:{target.isoformat()}"
    state_mod.upsert_episode(
        state_mod.EpisodeRow(
            id=episode_id,
            topic=topic_slug,
            episode_date=target.isoformat(),
            title=title,
            audio_path=str(mp3_path),
            audio_url=audio_url,
            duration_seconds=synth_meta["duration_seconds"],
            size_bytes=synth_meta["size_bytes"],
            summary=summary,
            script={"utterances": script_obj, "items": _strip_for_storage(summarized)},
            created_at=datetime.now(timezone.utc).isoformat(),
        )
    )

    state_mod.remember_sources(
        topic_slug,
        [(dedupe.normalize_url(c.get("url") or ""), c.get("title") or "") for c in summarized],
    )

    feed_path = rss_mod.write_feed(topic_slug, topic.title, topic.description)

    return {
        "episode_id": episode_id,
        "topic_slug": topic_slug,
        "target_date": target.isoformat(),
        "title": title,
        "audio_path": str(mp3_path),
        "audio_url": audio_url,
        "duration_seconds": synth_meta["duration_seconds"],
        "size_bytes": synth_meta["size_bytes"],
        "feed_path": str(feed_path),
        "feed_url": f"{cfg.public_base_url()}/{topic_slug}/feed.xml",
        "items": [
            {
                "title": s.get("title"),
                "url": s.get("url"),
                "source": s.get("source"),
                "score": s.get("score"),
                "summary_ja": s.get("summary_ja"),
                "takeaway_ja": s.get("takeaway_ja"),
            }
            for s in summarized
        ],
    }


def list_topics(**_: Any) -> dict[str, Any]:
    try:
        topics = cfg.load_topics()
    except Exception as exc:
        return {"error": f"failed to load topics.toml: {exc}"}
    return {
        "topics_toml": str(cfg.topics_toml_path()),
        "topics": [
            {
                "slug": t.slug,
                "title": t.title,
                "description": t.description,
                "voicevox_speaker_id": t.voicevox_speaker_id,
                "target_segment_count": t.target_segment_count,
                "sources": [
                    {"type": s.type, **s.extra} for s in t.sources
                ],
            }
            for t in topics
        ],
    }


def add_topic(
    *,
    slug: str,
    title: str,
    description: str,
    sources: list[dict[str, Any]],
    voicevox_speaker_id: int | None = None,
    target_segment_count: int | None = None,
    **_: Any,
) -> dict[str, Any]:
    existing = cfg.load_topics()
    if any(t.slug == slug for t in existing):
        return {"error": f"topic already exists: {slug}"}

    if not isinstance(sources, list) or not sources:
        return {"error": "sources must be a non-empty list"}

    accepted_types = set(sources_mod.available())
    for s in sources:
        if not isinstance(s, dict) or "type" not in s:
            return {"error": "each source must be a dict with a 'type' field"}
        if s["type"] not in accepted_types:
            return {
                "error": f"unknown source type: {s['type']}",
                "hint": f"supported: {sorted(accepted_types)}",
            }

    new_topic = {
        "slug": slug,
        "title": title,
        "description": description,
        "voicevox_speaker_id": voicevox_speaker_id or cfg._default_speaker_id(),
        "target_segment_count": target_segment_count or cfg.DEFAULT_SEGMENT_COUNT,
        "sources": sources,
    }
    cfg.append_topic_to_toml(new_topic)
    return {
        "added": slug,
        "topics_toml": str(cfg.topics_toml_path()),
        "next_steps": (
            "新トピックを定期生成するなら、hosts/khali/podcast-timer.nix の "
            "timer 群に systemd.timers.\"hermes-daily-podcast@<slug>\" を追加して "
            "nixos-rebuild switch してください。"
        ),
    }


def list_episodes(*, topic_slug: str, limit: int = 10, **_: Any) -> dict[str, Any]:
    rows = state_mod.list_episodes(topic_slug, limit=limit)
    return {
        "topic_slug": topic_slug,
        "episodes": [
            {
                "id": r.id,
                "episode_date": r.episode_date,
                "title": r.title,
                "audio_url": r.audio_url,
                "duration_seconds": r.duration_seconds,
                "created_at": r.created_at,
            }
            for r in rows
        ],
    }


def regenerate_episode(
    *, episode_id: str, hint: str | None = None, **_: Any
) -> dict[str, Any]:
    row = state_mod.get_episode(episode_id)
    if row is None:
        return {"error": f"unknown episode_id: {episode_id}"}
    return generate_daily_episode(
        topic_slug=row.topic, target_date=row.episode_date, hint=hint
    )


def generate_all_today_episodes(
    *, hint: str | None = None, target_date: str | None = None, **_: Any
) -> dict[str, Any]:
    """Run `generate_daily_episode` for every topic in topics.toml.

    Intended for the daily Hermes cron job. Returns one result envelope per
    topic so Discord delivery (or just log review) can see what succeeded vs
    what was skipped. A single topic failing never stops the rest.
    """
    try:
        topics = cfg.load_topics()
    except Exception as exc:
        return {"error": f"failed to load topics.toml: {exc}"}

    if not topics:
        return {"warning": "no topics defined", "results": []}

    results: list[dict[str, Any]] = []
    for t in topics:
        try:
            r = generate_daily_episode(
                topic_slug=t.slug, target_date=target_date, hint=hint
            )
        except Exception as exc:  # pragma: no cover - defensive
            logger.exception("daily-podcast generate_all: topic %s crashed", t.slug)
            r = {"error": f"{type(exc).__name__}: {exc}", "topic_slug": t.slug}
        results.append({"topic_slug": t.slug, "result": r})

    ok = sum(1 for r in results if "error" not in (r["result"] or {}))
    return {
        "summary": f"{ok}/{len(results)} topics generated",
        "results": results,
    }


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


def _resolve_target_date(target_date: str | None) -> date_cls:
    if not target_date:
        return datetime.now(ZoneInfo(cfg.DEFAULT_TIMEZONE)).date()
    return date_cls.fromisoformat(target_date)


def _japanese_date(d: date_cls) -> str:
    return f"{d.year}年{d.month}月{d.day}日"


def _strip_for_storage(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    keep = (
        "url",
        "title",
        "summary",
        "source",
        "score",
        "score_reason",
        "summary_ja",
        "takeaway_ja",
        "points",
        "comments",
    )
    out: list[dict[str, Any]] = []
    for s in items:
        out.append({k: s.get(k) for k in keep if k in s})
    return out
