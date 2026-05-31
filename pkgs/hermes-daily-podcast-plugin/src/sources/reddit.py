"""Reddit fetcher via the public `.rss` (Atom 1.0) endpoint.

As of 2026 Q2 the anonymous JSON endpoints (`/r/<sub>/top.json`) globally
return 403 for unauthenticated clients with non-Reddit User-Agents. The
`.rss` endpoint at `https://www.reddit.com/r/<sub>/top/.rss?t=day` is still
publicly accessible.

Trade-offs vs. the old JSON path:

- ✓ No 403, no OAuth required
- ✗ `score` / `num_comments` are not present in the RSS payload, so we can't
  apply `min_score` here. The downstream LLM scorer remains the authoritative
  relevance filter, so this matters less than it sounds.
- ✗ The `link` in each entry points at the Reddit comments page; external
  URLs (when present) live inside the entry HTML body as `[link]` anchors.
  We extract them when we can; otherwise we keep the comments URL.

Phase 2 will swap this for `asyncpraw` (OAuth, 60 req/min) but the RSS
fallback is robust enough to ship today.
"""

from __future__ import annotations

import logging
import re
import time
from datetime import datetime, timezone
from html import unescape
from typing import Any

from . import register
from .. import config as cfg
from .. import http

logger = logging.getLogger(__name__)

# Reddit anti-bot blocks the plugin's default UA. A browser-shaped UA gets
# through reliably; we still self-identify in the URL params if needed.
REDDIT_UA = (
    "Mozilla/5.0 (X11; Linux x86_64; rv:124.0) Gecko/20100101 Firefox/124.0"
)

INTER_REQUEST_SLEEP = 3.0
MAX_ATTEMPTS = 3


@register("reddit")
def fetch(source: cfg.SourceConfig) -> list[dict[str, Any]]:
    sub = (source.extra.get("subreddit") or "").strip()
    if not sub:
        logger.warning("daily-podcast reddit: source missing 'subreddit'")
        return []

    timeframe = source.extra.get("timeframe", "day")
    limit = int(source.extra.get("limit", 25))

    url = f"https://www.reddit.com/r/{sub}/top/.rss"
    params = {"t": timeframe, "limit": str(limit)}
    headers = {"User-Agent": REDDIT_UA}

    backoff = INTER_REQUEST_SLEEP
    raw: bytes | None = None
    for attempt in range(MAX_ATTEMPTS):
        try:
            raw = http.get_bytes(url, params=params, headers=headers)
            break
        except http.HttpError as exc:
            if exc.status in (429, 403, 503) and attempt < MAX_ATTEMPTS - 1:
                logger.warning(
                    "daily-podcast reddit r/%s: %s; retrying in %.0fs",
                    sub,
                    exc,
                    backoff,
                )
                time.sleep(backoff)
                backoff *= 2
                continue
            logger.warning("daily-podcast reddit r/%s: %s", sub, exc)
            return []

    if raw is None:
        return []

    # Stay polite even on success — the next sub fetch shouldn't follow
    # immediately.
    time.sleep(INTER_REQUEST_SLEEP)
    return _parse_atom(raw, sub)


# ---------------------------------------------------------------------------
# Atom parsing
# ---------------------------------------------------------------------------


def _parse_atom(raw: bytes, sub: str) -> list[dict[str, Any]]:
    """Parse Reddit's Atom 1.0 output. Prefer feedparser, fall back to stdlib."""
    try:
        import feedparser

        parsed = feedparser.parse(raw)
        entries = list(parsed.entries or [])
        if entries:
            return [_entry_from_feedparser(e, sub) for e in entries if _entry_is_usable(e)]
    except ImportError:
        pass
    except Exception:  # pragma: no cover - defensive
        logger.exception("daily-podcast reddit r/%s: feedparser failed", sub)

    return _parse_atom_stdlib(raw, sub)


def _entry_is_usable(e: Any) -> bool:
    return bool((e.get("title") or "").strip() and (e.get("link") or e.get("id")))


def _entry_from_feedparser(e: Any, sub: str) -> dict[str, Any]:
    title = (e.get("title") or "").strip()
    permalink = e.get("link") or e.get("id") or ""
    body_html = _feedparser_body(e)
    external = _extract_external_link(body_html, comments_url=permalink)
    return {
        "url": external or permalink,
        "title": title,
        "summary": _strip_html(body_html)[:500],
        "points": None,
        "comments": None,
        "published_at": _normalize_ts(e.get("published") or e.get("updated")),
        "reddit_url": permalink,
        "subreddit": sub,
        "language_hint": "en",
    }


def _feedparser_body(e: Any) -> str:
    content = e.get("content")
    if isinstance(content, list) and content:
        try:
            return content[0].get("value", "") or ""
        except AttributeError:
            return ""
    return (e.get("summary") or "") or ""


def _parse_atom_stdlib(raw: bytes, sub: str) -> list[dict[str, Any]]:
    """Fallback parser using only the standard library."""
    import xml.etree.ElementTree as ET

    ns = {"atom": "http://www.w3.org/2005/Atom"}
    try:
        root = ET.fromstring(raw)
    except ET.ParseError as exc:
        logger.warning("daily-podcast reddit r/%s: XML parse failed: %s", sub, exc)
        return []

    out: list[dict[str, Any]] = []
    for entry in root.findall("atom:entry", ns):
        title = (entry.findtext("atom:title", default="", namespaces=ns) or "").strip()
        link_el = entry.find("atom:link", ns)
        permalink = (link_el.get("href") if link_el is not None else "") or ""
        if not title or not permalink:
            continue
        content_el = entry.find("atom:content", ns)
        body_html = (content_el.text if content_el is not None else "") or ""
        external = _extract_external_link(body_html, comments_url=permalink)
        out.append(
            {
                "url": external or permalink,
                "title": title,
                "summary": _strip_html(body_html)[:500],
                "points": None,
                "comments": None,
                "published_at": _normalize_ts(
                    entry.findtext("atom:published", namespaces=ns)
                    or entry.findtext("atom:updated", namespaces=ns)
                ),
                "reddit_url": permalink,
                "subreddit": sub,
                "language_hint": "en",
            }
        )
    return out


# ---------------------------------------------------------------------------
# Body helpers
# ---------------------------------------------------------------------------


_HREF_RE = re.compile(r'href="([^"]+)"', re.I)


def _extract_external_link(html: str, *, comments_url: str) -> str | None:
    """Pull the cross-post target URL out of Reddit's RSS content HTML.

    Self-posts have only an internal `[comments]` link → return None so the
    caller falls back to the permalink. Link-posts include an `[link]` anchor
    pointing at the external URL; we return the first href that's not the
    comments page and not another Reddit domain.
    """
    if not html:
        return None
    for m in _HREF_RE.finditer(html):
        candidate = unescape(m.group(1)).strip()
        if not candidate:
            continue
        if candidate == comments_url:
            continue
        if _is_reddit_internal(candidate):
            continue
        return candidate
    return None


def _is_reddit_internal(url: str) -> bool:
    return any(
        host in url for host in ("reddit.com", "redd.it", "www.redditmedia.com")
    )


_TAG_RE = re.compile(r"<[^>]+>")
_WHITESPACE_RE = re.compile(r"\s+")


def _strip_html(html: str) -> str:
    if not html:
        return ""
    return _WHITESPACE_RE.sub(" ", unescape(_TAG_RE.sub(" ", html))).strip()


def _normalize_ts(s: Any) -> str | None:
    if not s:
        return None
    try:
        return (
            datetime.fromisoformat(str(s).replace("Z", "+00:00"))
            .astimezone(timezone.utc)
            .isoformat()
        )
    except ValueError:
        return str(s)
