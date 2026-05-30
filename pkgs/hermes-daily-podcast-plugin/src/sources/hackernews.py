"""Hacker News fetcher via the Algolia search endpoint.

Algolia is preferred over the Firebase API for our use case: it has built-in
search and `numericFilters` for points / num_comments thresholds, which
removes the need to fetch and filter every item client-side.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

from . import register
from .. import config as cfg
from .. import http

logger = logging.getLogger(__name__)

ALGOLIA_BASE = "https://hn.algolia.com/api/v1/search"


@register("hackernews")
def fetch(source: cfg.SourceConfig) -> list[dict[str, Any]]:
    query = (source.extra.get("query") or "").strip()
    if not query:
        logger.warning("daily-podcast hackernews: source missing 'query'")
        return []

    min_points = int(source.extra.get("min_points", 30))
    min_comments = int(source.extra.get("min_comments", 5))
    hits_per_page = int(source.extra.get("limit", 30))

    params = {
        "query": query,
        "tags": "story",
        "numericFilters": f"points>={min_points},num_comments>={min_comments}",
        "hitsPerPage": hits_per_page,
    }
    try:
        data = http.get_json(ALGOLIA_BASE, params=params)
    except http.HttpError as exc:
        logger.warning("daily-podcast hackernews: %s", exc)
        return []

    out: list[dict[str, Any]] = []
    for hit in data.get("hits", []):
        url = hit.get("url") or f"https://news.ycombinator.com/item?id={hit.get('objectID')}"
        title = hit.get("title") or hit.get("story_title") or ""
        if not title:
            continue
        created_at = hit.get("created_at")  # already ISO 8601 from Algolia
        out.append(
            {
                "url": url,
                "title": title,
                "summary": (hit.get("story_text") or "")[:500],
                "points": hit.get("points"),
                "comments": hit.get("num_comments"),
                "published_at": _normalize_ts(created_at),
                "hn_url": f"https://news.ycombinator.com/item?id={hit.get('objectID')}",
                "language_hint": "en",
            }
        )
    return out


def _normalize_ts(s: str | None) -> str | None:
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(
            timezone.utc
        ).isoformat()
    except ValueError:
        return s
