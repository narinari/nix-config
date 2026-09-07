"""Thin OpenAI-compatible chat completions client targeting aperture.

aperture forwards to hail-mary's Ollama (MLX backend) over Tailscale; auth is
handled by Tailscale identity at the aperture layer, but we still send
`OPENAI_API_KEY` so the SDK happy-path works. The plugin never reads the
*value* of the key as security material.
"""

from __future__ import annotations

import json
import logging
import re
from typing import Any

from . import config as cfg

logger = logging.getLogger(__name__)

DEFAULT_TIMEOUT_SECONDS = 300.0  # 35B 推論は遅いので余裕を見る


class LlmError(RuntimeError):
    pass


def chat(
    messages: list[dict[str, Any]],
    *,
    model: str | None = None,
    temperature: float = 0.3,
    max_tokens: int | None = None,
    response_format_json: bool = False,
    disable_thinking: bool = False,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
) -> str:
    """Call /v1/chat/completions and return the assistant string."""
    if disable_thinking:
        messages = _with_no_think(messages)
    body: dict[str, Any] = {
        "model": model or cfg.llm_model(),
        "messages": messages,
        "temperature": temperature,
        "stream": False,
    }
    if disable_thinking:
        # Ollama native パラメータ。OpenAI-compat 経由で無視されても無害。
        body["think"] = False
    if max_tokens is not None:
        body["max_tokens"] = max_tokens
    if response_format_json:
        # Ollama/llama.cpp ともに JSON モードをサポートする tag が多い
        body["response_format"] = {"type": "json_object"}

    url = f"{cfg.llm_base_url()}/chat/completions"
    headers = {
        "Authorization": f"Bearer {cfg.llm_api_key() or 'aperture-tailscale-identity'}",
        "Content-Type": "application/json",
    }

    payload = json.dumps(body, ensure_ascii=False).encode("utf-8")
    raw = _post(url, payload, headers, timeout)
    data = json.loads(raw.decode("utf-8"))
    try:
        return data["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError) as exc:
        raise LlmError(f"unexpected LLM response shape: {data!r}") from exc


def chat_json(
    messages: list[dict[str, Any]],
    *,
    model: str | None = None,
    temperature: float = 0.1,
    max_tokens: int | None = None,
    disable_thinking: bool = False,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
) -> Any:
    """Same as chat() but parses the response as JSON.

    Strips fenced code blocks (```json ... ```) which qwen often emits even
    with response_format_json set, and inline `<think>...</think>` blocks
    that leak into content on some model/template combinations.
    """
    text = chat(
        messages,
        model=model,
        temperature=temperature,
        max_tokens=max_tokens,
        response_format_json=True,
        disable_thinking=disable_thinking,
        timeout=timeout,
    )
    cleaned = _strip_code_fence(_strip_think_tags(text)).strip()
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError as exc:
        # Last-ditch: find the first '{' and last '}' and try again. Saves us
        # when the model adds a "Here is your JSON:" preamble.
        start = cleaned.find("{")
        end = cleaned.rfind("}")
        if start >= 0 and end > start:
            try:
                return json.loads(cleaned[start : end + 1])
            except json.JSONDecodeError:
                pass
        raise LlmError(f"LLM did not return valid JSON: {cleaned[:300]!r}") from exc


def _with_no_think(messages: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Return a copy of `messages` with `/no_think` appended to the system
    prompt (qwen3 soft switch). Prepends a system message if none exists."""
    out = [dict(m) for m in messages]
    for m in out:
        if m.get("role") == "system":
            m["content"] = f"{m.get('content', '')}\n/no_think"
            return out
    return [{"role": "system", "content": "/no_think"}, *out]


def _strip_think_tags(text: str) -> str:
    return re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL)


def _strip_code_fence(text: str) -> str:
    s = text.strip()
    if not s.startswith("```"):
        return s
    # ```json\n...\n```
    first_nl = s.find("\n")
    if first_nl < 0:
        return s
    s = s[first_nl + 1 :]
    if s.endswith("```"):
        s = s[: -3]
    return s


def _post(url: str, payload: bytes, headers: dict[str, str], timeout: float) -> bytes:
    """POST and return the body. Every transport failure surfaces as LlmError
    so callers can rely on a single exception type — a bare httpx.ReadTimeout
    once slipped through here and crashed a whole topic's generation."""
    try:
        import httpx
    except ImportError:
        return _post_urllib(url, payload, headers, timeout)

    try:
        resp = httpx.post(url, content=payload, headers=headers, timeout=timeout)
    except httpx.HTTPError as exc:
        raise LlmError(f"{url}: {type(exc).__name__}: {exc}") from exc
    if resp.status_code >= 400:
        raise LlmError(f"{url} -> {resp.status_code}: {resp.text[:300]}")
    return resp.content


def _post_urllib(
    url: str, payload: bytes, headers: dict[str, str], timeout: float
) -> bytes:
    from urllib import error as urlerr
    from urllib import request as urlreq

    req = urlreq.Request(url, data=payload, headers=headers, method="POST")
    try:
        with urlreq.urlopen(req, timeout=timeout) as resp:
            return resp.read()
    except urlerr.HTTPError as exc:
        raise LlmError(f"{url} -> {exc.code}: {exc.reason}") from exc
    except urlerr.URLError as exc:
        raise LlmError(f"{url}: {exc}") from exc
    except TimeoutError as exc:
        raise LlmError(f"{url}: timed out") from exc
