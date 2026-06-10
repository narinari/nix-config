"""Shared HTTP utilities for source fetchers.

Thin shim over `_vendor.last30days.http`. The vendor module gives us
Retry-After / 429 backoff, DNS gaierror retries, and secret-masked logging
without the plugin growing its own retry policy. The shim preserves the
``HttpError(status, message)`` / ``get_json`` / ``get_bytes`` API the
existing fetchers were written against, so they remain unchanged.

The previous httpx-based implementation is gone; stdlib (via the vendor
module) is enough and removes the optional dependency.
"""

from __future__ import annotations

import logging
from typing import Any

from ._vendor.last30days import http as _vendor_http

logger = logging.getLogger(__name__)

DEFAULT_TIMEOUT_SECONDS = 30.0


class HttpError(RuntimeError):
    """Backwards-compatible alias for vendor HTTPError.

    Exposes ``status`` (existing fetcher code reads this attribute) and
    ``body`` (set when the vendor captured the response body).
    """

    def __init__(
        self,
        status: int | None,
        message: str,
        *,
        body: str | None = None,
    ):
        super().__init__(message)
        self.status = status
        self.body = body

    @classmethod
    def _from_vendor(cls, exc: _vendor_http.HTTPError) -> "HttpError":
        return cls(exc.status_code, str(exc), body=exc.body)


def get_json(
    url: str,
    *,
    params: dict[str, Any] | None = None,
    headers: dict[str, str] | None = None,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
) -> Any:
    try:
        return _vendor_http.request(
            "GET",
            url,
            headers=dict(headers) if headers else None,
            params=params,
            timeout=int(timeout),
        )
    except _vendor_http.HTTPError as exc:
        raise HttpError._from_vendor(exc) from exc


def get_bytes(
    url: str,
    *,
    params: dict[str, Any] | None = None,
    headers: dict[str, str] | None = None,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
) -> bytes:
    try:
        text = _vendor_http.request(
            "GET",
            url,
            headers=dict(headers) if headers else None,
            params=params,
            timeout=int(timeout),
            raw=True,
        )
    except _vendor_http.HTTPError as exc:
        raise HttpError._from_vendor(exc) from exc
    if isinstance(text, (bytes, bytearray)):
        return bytes(text)
    return text.encode("utf-8")


def post_json(
    url: str,
    *,
    json: dict[str, Any],
    headers: dict[str, str] | None = None,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
) -> Any:
    """POST JSON helper. Added for new source adapters (e.g. xAI Live Search)."""
    try:
        return _vendor_http.request(
            "POST",
            url,
            headers=dict(headers) if headers else None,
            json_data=json,
            timeout=int(timeout),
        )
    except _vendor_http.HTTPError as exc:
        raise HttpError._from_vendor(exc) from exc


__all__ = [
    "HttpError",
    "get_json",
    "get_bytes",
    "post_json",
    "DEFAULT_TIMEOUT_SECONDS",
]
