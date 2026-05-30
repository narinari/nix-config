"""Reddit fetcher (anonymous JSON, Phase 1).

Reddit's anonymous endpoints still work in 2026 but are rate-limited to about
10 requests per minute. We do a small per-source sleep between calls and back
off on 429. A future Phase 2 swap to OAuth (`asyncpraw`) is straightforward
since the data shape is mostly the same.
"""

from __future__ import annotations

import logging
import os
import time
from datetime import datetime, timezone
from typing import Any

from . import register
from .. import config as cfg
from .. import http

logger = logging.getLogger(__name__)

ENV_UA = "REDDIT_USER_AGENT"
DEFAULT_UA = "hermes-daily-podcast/0.1 by /u/anonymous"
INTER_REQUEST_SLEEP = 6.0  # seconds


def _ua() -> str:
    return os.environ.get(ENV_UA, DEFAULT_UA).strip() or DEFAULT_UA


@register("reddit")
def fetch(source: cfg.SourceConfig) -> list[dict[str, Any]]:
    sub = (source.extra.get("subreddit") or "").strip()
    if not sub:
        logger.warning("daily-podcast reddit: source missing 'subreddit'")
        return []
    timeframe = source.extra.get("timeframe", "day")
    limit = int(source.extra.get("limit", 25))
    min_score = int(source.extra.get("min_score", 10))

    url = f"https://www.reddit.com/r/{sub}/top.json"
    params = {"t": timeframe, "limit": str(limit)}

    backoff = INTER_REQUEST_SLEEP
    for attempt in range(3):
        try:
            data = http.get_json(url, params=params, headers={"User-Agent": _ua()})
            break
        except http.HttpError as exc:
            if exc.status == 429 and attempt < 2:
                logger.warning(
                    "daily-podcast reddit r/%s: 429, backing off %.0fs", sub, backoff
                )
                time.sleep(backoff)
                backoff *= 2
                continue
            logger.warning("daily-podcast reddit r/%s: %s", sub, exc)
            return []
    else:
        return []

    # Rate-limit politely so the next subreddit fetch in the same run doesn't
    # immediately 429 us.
    time.sleep(INTER_REQUEST_SLEEP)

    children = (data.get("data") or {}).get("children") or []
    out: list[dict[str, Any]] = []
    for c in children:
        d = c.get("data") or {}
        score = d.get("score") or 0
        if score < min_score:
            continue
        permalink = d.get("permalink") or ""
        external_url = d.get("url_overridden_by_dest") or d.get("url") or ""
        # prefer external link when it's clearly not the comments page
        is_external = bool(external_url) and "reddit.com" not in external_url
        out.append(
            {
                "url": external_url if is_external else f"https://reddit.com{permalink}",
                "title": d.get("title") or "",
                "summary": (d.get("selftext") or "")[:500],
                "points": score,
                "comments": d.get("num_comments"),
                "published_at": _ts(d.get("created_utc")),
                "reddit_url": f"https://reddit.com{permalink}",
                "subreddit": sub,
                "language_hint": "en",
            }
        )
    return out


def _ts(epoch: Any) -> str | None:
    if epoch is None:
        return None
    try:
        return datetime.fromtimestamp(float(epoch), tz=timezone.utc).isoformat()
    except (TypeError, ValueError):
        return None
