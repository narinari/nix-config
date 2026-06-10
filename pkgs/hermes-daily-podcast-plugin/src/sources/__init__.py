"""Source fetchers.

Each fetcher exposes `fetch(source_config) -> list[Candidate]`. `Candidate`
is a plain dict so it can be JSON-serialized for debugging and LLM prompts
without further conversion.
"""

from __future__ import annotations

import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any, Callable

from .. import config as cfg

logger = logging.getLogger(__name__)

# Each candidate dict has at minimum:
#   url, title, summary?, source (type label), score? (set by score.py),
#   published_at? (ISO 8601), points?, comments?
Candidate = dict[str, Any]

_REGISTRY: dict[str, Callable[[cfg.SourceConfig], list[Candidate]]] = {}

# Per-source fetch timeout (seconds). Beyond this the worker is abandoned
# so a single hung source can't stall episode generation.
PER_SOURCE_TIMEOUT_SECONDS = 90.0
MAX_PARALLEL_WORKERS = 8


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
    """Fetch every source in parallel.

    Failures in any one source are isolated by ``fetch_one`` (which returns
    ``[]`` instead of raising). The output is concatenated in the order of
    ``sources`` so deterministic logs and dedupe ordering carry over from the
    serial implementation.

    A per-source ``PER_SOURCE_TIMEOUT_SECONDS`` cap keeps a single hung source
    (DNS hang, deadlocked SDK call) from blocking episode generation.
    """
    if not sources:
        return []

    results: list[list[Candidate]] = [[] for _ in sources]
    max_workers = min(MAX_PARALLEL_WORKERS, len(sources))

    with ThreadPoolExecutor(
        max_workers=max_workers,
        thread_name_prefix="daily-podcast-fetch",
    ) as executor:
        future_to_index = {
            executor.submit(fetch_one, source): index
            for index, source in enumerate(sources)
        }
        for future in as_completed(future_to_index):
            index = future_to_index[future]
            source = sources[index]
            try:
                items = future.result(timeout=PER_SOURCE_TIMEOUT_SECONDS)
            except Exception:
                logger.exception(
                    "daily-podcast: source %s timed out or crashed; dropping",
                    source.type,
                )
                continue
            for item in items:
                item.setdefault("source", source.type)
            results[index] = items

    flattened: list[Candidate] = []
    for items in results:
        flattened.extend(items)
    return flattened


# Importing the submodules triggers @register decorators.
from . import hackernews  # noqa: E402,F401
from . import bluesky  # noqa: E402,F401
from . import hatena  # noqa: E402,F401
from . import reddit  # noqa: E402,F401
from . import github  # noqa: E402,F401
from . import polymarket  # noqa: E402,F401
from . import youtube  # noqa: E402,F401
from . import x as _x_source  # noqa: E402,F401
