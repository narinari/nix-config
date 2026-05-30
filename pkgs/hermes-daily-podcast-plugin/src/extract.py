"""Article body extraction for summarization input.

Trafilatura is the primary; if it (or its dep `lxml`) isn't installed, we fall
back to a best-effort raw HTML grab so the pipeline still works on a degraded
quality budget instead of crashing.
"""

from __future__ import annotations

import logging
from typing import Any

from . import http

logger = logging.getLogger(__name__)

MAX_BODY_CHARS = 8000


def extract(url: str, *, timeout: float = 15.0) -> str:
    """Return cleaned article body text (best effort). Empty string on failure."""
    if not url:
        return ""
    try:
        html = http.get_bytes(url, timeout=timeout)
    except http.HttpError as exc:
        logger.info("daily-podcast extract: HTTP fail for %s: %s", url, exc)
        return ""

    try:
        import trafilatura
    except ImportError:
        return _strip_html_tags(html.decode("utf-8", errors="ignore"))[
            :MAX_BODY_CHARS
        ]

    try:
        body = trafilatura.extract(
            html,
            output="txt",
            include_comments=False,
            include_tables=False,
        )
    except Exception as exc:  # pragma: no cover - defensive
        logger.info("daily-podcast extract: trafilatura raised for %s: %s", url, exc)
        body = None
    if not body:
        return ""
    return body[:MAX_BODY_CHARS]


def _strip_html_tags(text: str) -> str:
    import re
    from html import unescape

    s = re.sub(r"<(script|style)[^>]*>.*?</\1>", " ", text, flags=re.S | re.I)
    s = re.sub(r"<[^>]+>", " ", s)
    s = unescape(s)
    return re.sub(r"\s+", " ", s).strip()
