"""Shared HTTP utilities for source fetchers.

httpx if available, urllib fallback. Always returns the response body as
bytes/text so callers can decide JSON vs RSS parsing.
"""

from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger(__name__)

DEFAULT_TIMEOUT_SECONDS = 30.0
DEFAULT_UA = "hermes-daily-podcast/0.1"


class HttpError(RuntimeError):
    def __init__(self, status: int | None, message: str):
        super().__init__(message)
        self.status = status


def get_json(
    url: str,
    *,
    params: dict[str, Any] | None = None,
    headers: dict[str, str] | None = None,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
) -> Any:
    body = _get(url, params=params, headers=headers, timeout=timeout)
    import json

    return json.loads(body.decode("utf-8"))


def get_bytes(
    url: str,
    *,
    params: dict[str, Any] | None = None,
    headers: dict[str, str] | None = None,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
) -> bytes:
    return _get(url, params=params, headers=headers, timeout=timeout)


def _get(
    url: str,
    *,
    params: dict[str, Any] | None,
    headers: dict[str, str] | None,
    timeout: float,
) -> bytes:
    merged_headers = {"User-Agent": DEFAULT_UA, "Accept": "*/*"}
    if headers:
        merged_headers.update(headers)
    try:
        import httpx
    except ImportError:
        return _get_stdlib(url, params=params, headers=merged_headers, timeout=timeout)

    try:
        # follow_redirects defaults to False on httpx >= 0.20; many feed
        # endpoints (e.g. Hatena tag search) 301 to a canonical URL, so we
        # opt in here.
        resp = httpx.get(
            url,
            params=params,
            headers=merged_headers,
            timeout=timeout,
            follow_redirects=True,
        )
        if resp.status_code >= 400:
            raise HttpError(resp.status_code, f"{url} -> {resp.status_code}")
        return resp.content
    except httpx.HTTPError as exc:
        raise HttpError(None, f"{url}: {exc}") from exc


def _get_stdlib(
    url: str,
    *,
    params: dict[str, Any] | None,
    headers: dict[str, str],
    timeout: float,
) -> bytes:
    from urllib import error as urlerr
    from urllib import request as urlreq
    from urllib.parse import urlencode

    full_url = url
    if params:
        sep = "&" if "?" in url else "?"
        full_url = f"{url}{sep}{urlencode(params, doseq=True)}"
    req = urlreq.Request(full_url, headers=headers)
    try:
        with urlreq.urlopen(req, timeout=timeout) as resp:
            return resp.read()
    except urlerr.HTTPError as exc:
        raise HttpError(exc.code, f"{full_url} -> {exc.code}: {exc.reason}") from exc
    except urlerr.URLError as exc:
        raise HttpError(None, f"{full_url}: {exc}") from exc
