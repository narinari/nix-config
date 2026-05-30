"""RSS feed generation for a topic.

Emits a feed at `<public_base_url>/<topic>/feed.xml` with iTunes namespace +
podcast 2.0 namespace (chapters URL, transcript). The transcript text is the
plain script joined with blank lines — written as a .txt sidecar.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path
from typing import Any
from xml.sax.saxutils import escape

from . import config as cfg
from . import state as state_mod

logger = logging.getLogger(__name__)


def write_feed(topic_slug: str, topic_title: str, topic_description: str) -> Path:
    """Render the RSS feed for `topic_slug` from the SQLite episodes table."""
    episodes = state_mod.list_episodes(topic_slug, limit=50)
    feed_path = cfg.episodes_dir() / topic_slug / "feed.xml"
    feed_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        xml = _render_with_feedgen(topic_slug, topic_title, topic_description, episodes)
    except ImportError:
        xml = _render_stdlib(topic_slug, topic_title, topic_description, episodes)

    feed_path.write_text(xml, encoding="utf-8")
    return feed_path


def write_transcript(topic_slug: str, episode_date: str, text: str) -> Path:
    out = cfg.episodes_dir() / topic_slug / f"{episode_date}.txt"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8")
    return out


def _episode_audio_url(topic_slug: str, episode_date: str) -> str:
    return f"{cfg.public_base_url()}/{topic_slug}/{episode_date}.mp3"


def _episode_transcript_url(topic_slug: str, episode_date: str) -> str:
    return f"{cfg.public_base_url()}/{topic_slug}/{episode_date}.txt"


def _cover_image_url() -> str:
    return f"{cfg.public_base_url()}/static/cover.png"


def _render_with_feedgen(
    topic_slug: str,
    topic_title: str,
    topic_description: str,
    episodes: list[state_mod.EpisodeRow],
) -> str:
    from feedgen.feed import FeedGenerator

    fg = FeedGenerator()
    fg.load_extension("podcast")
    feed_self = f"{cfg.public_base_url()}/{topic_slug}/feed.xml"
    fg.id(feed_self)
    fg.title(topic_title)
    fg.description(topic_description or topic_title)
    fg.link(href=feed_self, rel="self")
    fg.language("ja")
    fg.podcast.itunes_category("Technology")
    fg.podcast.itunes_explicit("no")
    fg.podcast.itunes_author(cfg.author())
    fg.podcast.itunes_owner(name=cfg.author(), email=cfg.owner_email())
    fg.podcast.itunes_image(_cover_image_url())
    fg.podcast.itunes_summary(topic_description or topic_title)

    for ep in episodes:
        fe = fg.add_entry()
        fe.id(ep.audio_url)
        fe.title(ep.title)
        fe.description(ep.summary or "")
        fe.enclosure(
            ep.audio_url,
            str(ep.size_bytes or 0),
            "audio/mpeg",
        )
        published_at = _safe_parse_iso(ep.created_at) or datetime.now(timezone.utc)
        fe.pubDate(published_at)
        if ep.duration_seconds:
            fe.podcast.itunes_duration(_hhmmss(ep.duration_seconds))
        fe.podcast.itunes_explicit("no")
        fe.podcast.itunes_image(_cover_image_url())

    return fg.rss_str(pretty=True).decode("utf-8")


def _render_stdlib(
    topic_slug: str,
    topic_title: str,
    topic_description: str,
    episodes: list[state_mod.EpisodeRow],
) -> str:
    """Hand-written RSS 2.0 fallback (no feedgen).

    Emits all iTunes elements that Apple Podcasts / Overcast require:
    `itunes:author`, `itunes:summary`, `itunes:explicit`, `itunes:category`,
    `itunes:image`, `itunes:owner`. Without these, Overcast rejects the feed
    with "Could not download podcast feed".
    """
    feed_self = f"{cfg.public_base_url()}/{topic_slug}/feed.xml"
    cover_url = _cover_image_url()
    author_name = cfg.author()
    owner_email_value = cfg.owner_email()
    items: list[str] = []
    for ep in episodes:
        pub_dt = _safe_parse_iso(ep.created_at) or datetime.now(timezone.utc)
        items.append(
            "<item>\n"
            f"  <guid isPermaLink=\"false\">{escape(ep.id)}</guid>\n"
            f"  <title>{escape(ep.title)}</title>\n"
            f"  <description>{escape(ep.summary or '')}</description>\n"
            f"  <pubDate>{format_datetime(pub_dt)}</pubDate>\n"
            f"  <enclosure url=\"{escape(ep.audio_url)}\" "
            f"length=\"{ep.size_bytes or 0}\" type=\"audio/mpeg\"/>\n"
            f"  <itunes:explicit>false</itunes:explicit>\n"
            f"  <itunes:image href=\"{escape(cover_url)}\"/>\n"
            + (
                f"  <itunes:duration>{_hhmmss(ep.duration_seconds)}</itunes:duration>\n"
                if ep.duration_seconds
                else ""
            )
            + "</item>"
        )
    items_xml = "\n".join(items)
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<rss version="2.0"\n'
        '     xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"\n'
        '     xmlns:atom="http://www.w3.org/2005/Atom"\n'
        '     xmlns:podcast="https://podcastindex.org/namespace/1.0">\n'
        "<channel>\n"
        f"  <title>{escape(topic_title)}</title>\n"
        f"  <description>{escape(topic_description or topic_title)}</description>\n"
        f"  <link>{escape(cfg.public_base_url())}</link>\n"
        f"  <language>ja</language>\n"
        f"  <generator>hermes-daily-podcast</generator>\n"
        f"  <itunes:author>{escape(author_name)}</itunes:author>\n"
        f"  <itunes:summary>{escape(topic_description or topic_title)}</itunes:summary>\n"
        f"  <itunes:explicit>false</itunes:explicit>\n"
        f'  <itunes:category text="Technology"/>\n'
        f'  <itunes:image href="{escape(cover_url)}"/>\n'
        f"  <itunes:owner>\n"
        f"    <itunes:name>{escape(author_name)}</itunes:name>\n"
        f"    <itunes:email>{escape(owner_email_value)}</itunes:email>\n"
        f"  </itunes:owner>\n"
        f"  <atom:link href=\"{escape(feed_self)}\" rel=\"self\" type=\"application/rss+xml\"/>\n"
        f"{items_xml}\n"
        "</channel></rss>\n"
    )


def _safe_parse_iso(s: str | None) -> datetime | None:
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None


def _hhmmss(seconds: int) -> str:
    s = int(seconds)
    h, rem = divmod(s, 3600)
    m, ss = divmod(rem, 60)
    return f"{h:02d}:{m:02d}:{ss:02d}"
