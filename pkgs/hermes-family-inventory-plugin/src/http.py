"""HTTP client for the family-inventory agent API.

Thin wrapper around httpx (preferred — already a Hermes runtime dep) that
translates OpenAPI operation invocations into authenticated requests and
returns plain Python dicts for the tool handler to JSON-encode.

Auth model: every call is identified by a static `X-API-Key` (per-environment
agent API key) plus a per-actor `X-Agent-Actor` header. Both are sourced from
process env so the secrets never touch the Nix store.
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any
from urllib.parse import urlencode

logger = logging.getLogger(__name__)

ENV_BASE_URL = "FAMILY_INVENTORY_API_URL"
ENV_API_KEY = "FAMILY_INVENTORY_AGENT_API_KEY"
ENV_ACTOR = "FAMILY_INVENTORY_AGENT_ACTOR"

DEFAULT_TIMEOUT_SECONDS = 30.0


class ConfigError(RuntimeError):
    """Raised when required env vars are missing or malformed."""


def _get_config() -> tuple[str, str, str]:
    """Return (base_url, api_key, actor) or raise ConfigError."""
    base_url = os.environ.get(ENV_BASE_URL, "").strip()
    api_key = os.environ.get(ENV_API_KEY, "").strip()
    actor = os.environ.get(ENV_ACTOR, "").strip()

    missing = [
        name
        for name, val in [
            (ENV_BASE_URL, base_url),
            (ENV_API_KEY, api_key),
            (ENV_ACTOR, actor),
        ]
        if not val
    ]
    if missing:
        raise ConfigError(
            "family-inventory plugin: missing env vars: " + ", ".join(missing)
        )

    return base_url.rstrip("/"), api_key, actor


def _format_path(path_template: str, path_params: dict[str, Any]) -> str:
    """Substitute OpenAPI path params, URL-encoding each value individually.

    Uses str.format so `/agent/items/{id}/location` + `{"id": "abc"}` becomes
    `/agent/items/abc/location`. Missing keys raise KeyError which the caller
    surfaces as an error dict.
    """
    from urllib.parse import quote

    encoded = {k: quote(str(v), safe="") for k, v in path_params.items()}
    return path_template.format(**encoded)


def request(
    method: str,
    path_template: str,
    *,
    path_params: dict[str, Any] | None = None,
    query_params: dict[str, Any] | None = None,
    json_body: dict[str, Any] | None = None,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
) -> dict[str, Any]:
    """Make an authenticated request and return a dict.

    On success: parsed JSON response body (always a dict per family-inventory
    response envelope convention).
    On error (network / non-2xx / decode): structured error dict
    `{"error": str, "status": int|None, "details": Any}` — never raises.
    """
    try:
        base_url, api_key, actor = _get_config()
    except ConfigError as exc:
        return {"error": str(exc), "status": None, "details": None}

    try:
        path = _format_path(path_template, path_params or {})
    except KeyError as exc:
        return {
            "error": f"missing path parameter: {exc.args[0]}",
            "status": None,
            "details": {"path_template": path_template},
        }

    url = f"{base_url}{path}"
    headers = {
        "X-API-Key": api_key,
        "X-Agent-Actor": actor,
        "Accept": "application/json",
    }
    if json_body is not None:
        headers["Content-Type"] = "application/json"

    # Prefer httpx (already in Hermes runtime); fall back to stdlib so a
    # missing dep doesn't break load. Behavior is identical from the caller's POV.
    try:
        import httpx  # type: ignore[import-untyped]
    except ImportError:
        return _request_stdlib(
            method=method,
            url=url,
            headers=headers,
            query_params=query_params or {},
            json_body=json_body,
            timeout=timeout,
        )

    try:
        with httpx.Client(timeout=timeout) as client:
            resp = client.request(
                method.upper(),
                url,
                params=query_params or None,
                json=json_body,
                headers=headers,
            )
    except httpx.TimeoutException as exc:
        return {"error": f"request timeout: {exc}", "status": None, "details": None}
    except httpx.HTTPError as exc:
        return {"error": f"http error: {exc}", "status": None, "details": None}
    except Exception as exc:  # pragma: no cover - defensive
        logger.exception("family-inventory: unexpected error during request")
        return {
            "error": f"unexpected error: {type(exc).__name__}: {exc}",
            "status": None,
            "details": None,
        }

    return _decode_response(resp.status_code, resp.content, resp.headers.get("content-type", ""))


def _request_stdlib(
    *,
    method: str,
    url: str,
    headers: dict[str, str],
    query_params: dict[str, Any],
    json_body: dict[str, Any] | None,
    timeout: float,
) -> dict[str, Any]:
    """Fallback HTTP request using urllib only. Same return contract as request()."""
    from urllib.error import HTTPError, URLError
    from urllib.request import Request, urlopen

    full_url = url
    if query_params:
        flat: list[tuple[str, str]] = []
        for k, v in query_params.items():
            if v is None:
                continue
            if isinstance(v, (list, tuple)):
                flat.extend((k, str(x)) for x in v)
            else:
                flat.append((k, str(v)))
        if flat:
            sep = "&" if "?" in full_url else "?"
            full_url = f"{full_url}{sep}{urlencode(flat)}"

    data: bytes | None = None
    if json_body is not None:
        data = json.dumps(json_body, ensure_ascii=False).encode("utf-8")

    req = Request(full_url, data=data, headers=headers, method=method.upper())
    try:
        with urlopen(req, timeout=timeout) as resp:
            body = resp.read()
            content_type = resp.headers.get("Content-Type", "")
            return _decode_response(resp.status, body, content_type)
    except HTTPError as exc:
        body = b""
        try:
            body = exc.read()
        except Exception:  # pragma: no cover
            pass
        return _decode_response(exc.code, body, exc.headers.get("Content-Type", "") if exc.headers else "")
    except URLError as exc:
        return {"error": f"network error: {exc.reason}", "status": None, "details": None}
    except Exception as exc:  # pragma: no cover - defensive
        logger.exception("family-inventory: unexpected error (stdlib path)")
        return {
            "error": f"unexpected error: {type(exc).__name__}: {exc}",
            "status": None,
            "details": None,
        }


def _decode_response(status: int, body: bytes, content_type: str) -> dict[str, Any]:
    """Convert an HTTP response into the plugin's dict contract."""
    parsed: Any = None
    if body:
        try:
            parsed = json.loads(body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            parsed = body[:2000].decode("utf-8", errors="replace")

    if 200 <= status < 300:
        if isinstance(parsed, dict):
            return parsed
        # Endpoints should always return a JSON object envelope; preserve raw
        # payload under "data" so the agent at least sees something useful.
        return {"success": True, "data": parsed, "status": status}

    return {
        "error": f"http {status}",
        "status": status,
        "details": parsed,
    }
