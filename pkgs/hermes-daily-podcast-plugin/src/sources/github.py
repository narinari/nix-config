"""GitHub Issues / Pull Requests fetcher via the public Search API.

Uses ``GET https://api.github.com/search/issues`` for issue & PR discovery,
sorted by reactions so the most-discussed topical activity floats up.

Auth tiers (resolved at fetch time, no per-source config needed):

1. ``GITHUB_TOKEN`` env (set via agenix ``daily-podcast-env.age``)
2. ``GH_TOKEN`` env (gh CLI alias — useful for local dev)
3. Unauthenticated (60 req/h shared by IP — barely enough for daily runs)

The unauth path stays alive on purpose: it lets a host bring up the topic
without provisioning a token, even though rate limits will bite quickly.
"""

from __future__ import annotations

import logging
import os
from datetime import datetime, timedelta, timezone
from typing import Any

from . import register
from .. import config as cfg
from .. import http
from ._common import normalize_ts, truncate

logger = logging.getLogger(__name__)

SEARCH_URL = "https://api.github.com/search/issues"


@register("github_issues")
def fetch(source: cfg.SourceConfig) -> list[dict[str, Any]]:
    query = (source.extra.get("query") or "").strip()
    if not query:
        logger.warning("daily-podcast github_issues: source missing 'query'")
        return []

    min_reactions = int(source.extra.get("min_reactions", 3))
    limit = int(source.extra.get("limit", 25))
    since_days = int(source.extra.get("since_days", 7))
    sort = (source.extra.get("sort") or "reactions").strip()
    order = (source.extra.get("order") or "desc").strip()

    since_date = (
        datetime.now(timezone.utc) - timedelta(days=since_days)
    ).strftime("%Y-%m-%d")

    q = f"{query} created:>{since_date}"
    params = {
        "q": q,
        "sort": sort,
        "order": order,
        "per_page": str(min(limit, 100)),
    }

    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    else:
        logger.debug(
            "daily-podcast github_issues: no GITHUB_TOKEN/GH_TOKEN; using "
            "anonymous quota (60 req/h)"
        )

    try:
        data = http.get_json(SEARCH_URL, params=params, headers=headers, timeout=30)
    except http.HttpError as exc:
        logger.warning("daily-podcast github_issues '%s': %s", query, exc)
        return []

    out: list[dict[str, Any]] = []
    for hit in data.get("items", []):
        reactions = hit.get("reactions") or {}
        total_reactions = int(reactions.get("total_count") or 0)
        if total_reactions < min_reactions:
            continue
        title = (hit.get("title") or "").strip()
        url = hit.get("html_url") or ""
        if not title or not url:
            continue
        body = hit.get("body") or ""
        labels = [
            (label.get("name") or "")
            for label in (hit.get("labels") or [])
            if isinstance(label, dict)
        ]
        is_pr = "pull_request" in hit
        out.append(
            {
                "url": url,
                "title": title,
                "summary": truncate(body, 500),
                "points": total_reactions,
                "comments": int(hit.get("comments") or 0),
                "published_at": normalize_ts(hit.get("created_at")),
                "language_hint": "en",
                "repo": _repo_from_url(url),
                "labels": labels,
                "is_pr": is_pr,
                "state": hit.get("state"),
            }
        )
    return out


def _repo_from_url(html_url: str) -> str:
    parts = html_url.replace("https://github.com/", "").split("/")
    if len(parts) >= 2:
        return f"{parts[0]}/{parts[1]}"
    return ""
