"""Shared helpers reused across multiple source fetchers."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any


def normalize_ts(value: Any) -> str | None:
    """Coerce an ISO 8601 string (with or without trailing ``Z``) into UTC ISO.

    Returns the input unchanged if it cannot be parsed — fetchers prefer
    "carry whatever the upstream gave us" over "drop the field entirely",
    since downstream ranking only uses ``published_at`` as a tie-breaker.
    """
    if not value:
        return None
    if isinstance(value, datetime):
        return value.astimezone(timezone.utc).isoformat()
    try:
        return (
            datetime.fromisoformat(str(value).replace("Z", "+00:00"))
            .astimezone(timezone.utc)
            .isoformat()
        )
    except ValueError:
        return str(value)


def truncate(text: str | None, limit: int) -> str:
    """Length-cap a string for downstream LLM prompts."""
    if not text:
        return ""
    text = text.strip()
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "…"
