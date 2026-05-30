"""Bluesky fetcher.

Search endpoints on Bluesky now require an authenticated session. We use the
`atproto` Python SDK with a Bluesky handle + app password supplied via env
(`BLUESKY_HANDLE`, `BLUESKY_APP_PASSWORD`). If the SDK or credentials are
missing, the fetcher logs a warning and returns an empty list — the rest of
the pipeline continues to work with whatever other sources succeeded.
"""

from __future__ import annotations

import logging
import os
from datetime import datetime, timezone
from typing import Any

from . import register
from .. import config as cfg

logger = logging.getLogger(__name__)

ENV_HANDLE = "BLUESKY_HANDLE"
ENV_APP_PASSWORD = "BLUESKY_APP_PASSWORD"


@register("bluesky")
def fetch(source: cfg.SourceConfig) -> list[dict[str, Any]]:
    query = (source.extra.get("query") or "").strip()
    if not query:
        logger.warning("daily-podcast bluesky: source missing 'query'")
        return []

    handle = os.environ.get(ENV_HANDLE, "").strip()
    app_password = os.environ.get(ENV_APP_PASSWORD, "").strip()
    if not handle or not app_password:
        logger.warning(
            "daily-podcast bluesky: %s / %s not set; skipping",
            ENV_HANDLE,
            ENV_APP_PASSWORD,
        )
        return []

    try:
        from atproto import Client
    except ImportError:
        logger.warning(
            "daily-podcast bluesky: atproto package not installed; skipping"
        )
        return []

    limit = int(source.extra.get("limit", 25))
    lang = source.extra.get("lang")

    try:
        client = Client()
        client.login(handle, app_password)
        params: dict[str, Any] = {"q": query, "limit": limit}
        if lang:
            params["lang"] = lang
        resp = client.app.bsky.feed.search_posts(params=params)
    except Exception:
        logger.exception("daily-podcast bluesky: search_posts failed")
        return []

    posts = getattr(resp, "posts", None) or []
    out: list[dict[str, Any]] = []
    for post in posts:
        try:
            author_handle = getattr(getattr(post, "author", None), "handle", "")
            record = getattr(post, "record", None)
            text = getattr(record, "text", "") or ""
            created = getattr(record, "created_at", None)
            uri = getattr(post, "uri", "") or ""
            web_url = _at_uri_to_web(uri, author_handle)
            out.append(
                {
                    "url": web_url or uri,
                    "title": _make_title(text, author_handle),
                    "summary": text[:500],
                    "points": getattr(post, "like_count", None),
                    "comments": getattr(post, "reply_count", None),
                    "published_at": _normalize_ts(created),
                    "language_hint": lang or "und",
                }
            )
        except Exception:  # pragma: no cover - defensive
            logger.exception("daily-podcast bluesky: malformed post skipped")
    return out


def _make_title(text: str, author: str) -> str:
    first_line = (text or "").splitlines()[0] if text else ""
    snippet = first_line.strip()[:80]
    if not snippet:
        snippet = "(no text)"
    return f"@{author}: {snippet}" if author else snippet


def _at_uri_to_web(uri: str, handle: str) -> str | None:
    # at://did:.../app.bsky.feed.post/<rkey> → https://bsky.app/profile/<handle>/post/<rkey>
    if not uri or not uri.startswith("at://"):
        return None
    parts = uri.split("/")
    if len(parts) < 5:
        return None
    rkey = parts[-1]
    if not handle:
        return None
    return f"https://bsky.app/profile/{handle}/post/{rkey}"


def _normalize_ts(s: Any) -> str | None:
    if not s:
        return None
    if isinstance(s, datetime):
        return s.astimezone(timezone.utc).isoformat()
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00")).astimezone(
            timezone.utc
        ).isoformat()
    except ValueError:
        return str(s)
