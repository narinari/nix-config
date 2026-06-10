"""Polymarket prediction market fetcher via Gamma API.

Uses ``GET https://gamma-api.polymarket.com/public-search`` for event &
market discovery. The endpoint is keyless and read-only with a generous
15K req / 10s quota, so there is no auth or rate-limit concern.

The fetcher only surfaces *active* events with at least one open market
that has liquidity — closed / resolved events are uninteresting for a
daily podcast.
"""

from __future__ import annotations

import json as _json
import logging
from typing import Any

from . import register
from .. import config as cfg
from .. import http
from ._common import normalize_ts, truncate

logger = logging.getLogger(__name__)

GAMMA_SEARCH_URL = "https://gamma-api.polymarket.com/public-search"


@register("polymarket")
def fetch(source: cfg.SourceConfig) -> list[dict[str, Any]]:
    query = (source.extra.get("query") or "").strip()
    if not query:
        logger.warning("daily-podcast polymarket: source missing 'query'")
        return []

    limit = int(source.extra.get("limit", 20))
    min_liquidity = float(source.extra.get("min_liquidity", 1000))

    params = {
        "q": query,
        "events_status": "active",
        "keep_closed_markets": "0",
    }

    try:
        data = http.get_json(GAMMA_SEARCH_URL, params=params, timeout=20)
    except http.HttpError as exc:
        logger.warning("daily-podcast polymarket '%s': %s", query, exc)
        return []

    out: list[dict[str, Any]] = []
    for event in (data or {}).get("events", []):
        if event.get("closed") or not event.get("active", True):
            continue
        markets = event.get("markets") or []
        active = _active_markets(markets, min_liquidity)
        if not active:
            continue
        top = active[0]
        title = (event.get("title") or top.get("question") or "").strip()
        slug = event.get("slug") or event.get("id")
        if not title or not slug:
            continue

        outcome_str = _format_outcomes(top)
        summary_parts = [top.get("question") or ""]
        if outcome_str:
            summary_parts.append(outcome_str)
        summary = truncate(" — ".join(p for p in summary_parts if p), 500)

        volume = _safe_float(event.get("volume24hr")) or _safe_float(
            top.get("volume24hr")
        )

        out.append(
            {
                "url": f"https://polymarket.com/event/{slug}",
                "title": title,
                "summary": summary,
                "points": int(volume) if volume else None,
                "comments": None,
                "published_at": normalize_ts(event.get("updatedAt")),
                "language_hint": "en",
                "outcome_prices": _parse_outcome_prices(top),
                "liquidity": _safe_float(top.get("liquidity")),
            }
        )

        if len(out) >= limit:
            break

    return out


def _active_markets(
    markets: list[dict[str, Any]], min_liquidity: float
) -> list[dict[str, Any]]:
    active: list[dict[str, Any]] = []
    for m in markets:
        if m.get("closed") or not m.get("active", True):
            continue
        if _safe_float(m.get("liquidity")) < min_liquidity:
            continue
        active.append(m)
    active.sort(key=lambda m: _safe_float(m.get("volume")), reverse=True)
    return active


def _parse_outcome_prices(market: dict[str, Any]) -> list[tuple[str, float]]:
    outcomes_raw = market.get("outcomes")
    prices_raw = market.get("outcomePrices")
    if not prices_raw:
        return []

    outcomes = _load_json_array(outcomes_raw)
    prices = _load_json_array(prices_raw)

    out: list[tuple[str, float]] = []
    for i, price in enumerate(prices):
        try:
            p = float(price)
        except (TypeError, ValueError):
            continue
        name = outcomes[i] if i < len(outcomes) else f"Outcome {i + 1}"
        out.append((str(name), p))
    return out


def _format_outcomes(market: dict[str, Any]) -> str:
    pairs = _parse_outcome_prices(market)
    if not pairs:
        return ""
    pairs.sort(key=lambda x: x[1], reverse=True)
    return ", ".join(f"{name}: {price * 100:.0f}%" for name, price in pairs[:3])


def _load_json_array(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    try:
        parsed = _json.loads(value)
    except (TypeError, ValueError, _json.JSONDecodeError):
        return []
    if isinstance(parsed, list):
        return parsed
    return []


def _safe_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default
