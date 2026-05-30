"""Source fetchers.

Each fetcher exposes `fetch(source_config) -> list[Candidate]`. `Candidate`
is a plain dict so it can be JSON-serialized for debugging and LLM prompts
without further conversion.
"""

from __future__ import annotations

import logging
from typing import Any, Callable

from .. import config as cfg

logger = logging.getLogger(__name__)

# Each candidate dict has at minimum:
#   url, title, summary?, source (type label), score? (set by score.py),
#   published_at? (ISO 8601), points?, comments?
Candidate = dict[str, Any]

_REGISTRY: dict[str, Callable[[cfg.SourceConfig], list[Candidate]]] = {}


def register(type_name: str):
    def deco(fn):
        _REGISTRY[type_name] = fn
        return fn

    return deco


def available() -> list[str]:
    return sorted(_REGISTRY.keys())


def fetch_one(source: cfg.SourceConfig) -> list[Candidate]:
    fn = _REGISTRY.get(source.type)
    if fn is None:
        logger.warning("daily-podcast: unknown source type %r — skipping", source.type)
        return []
    try:
        return fn(source)
    except Exception:
        logger.exception(
            "daily-podcast: fetcher for %s failed; returning empty", source.type
        )
        return []


def fetch_all(sources: list[cfg.SourceConfig]) -> list[Candidate]:
    results: list[Candidate] = []
    for s in sources:
        items = fetch_one(s)
        for item in items:
            item.setdefault("source", s.type)
        results.extend(items)
    return results


# Importing the submodules triggers @register decorators.
from . import hackernews  # noqa: E402,F401
from . import bluesky  # noqa: E402,F401
from . import hatena  # noqa: E402,F401
from . import reddit  # noqa: E402,F401
