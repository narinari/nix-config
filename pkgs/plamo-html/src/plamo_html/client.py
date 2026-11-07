"""llama-server /v1/completions クライアント (標準ライブラリのみ)。"""

from __future__ import annotations

import json
import socket
import time
import urllib.error
import urllib.request
from typing import Callable, Protocol

from plamo_html.errors import ServerError, ServerUnreachable

MODEL_NAME = "plamo-3-translate"
STOP_SEQUENCES = ["<|plamo:tag|>", "<|plamo:bos|>"]
TIMEOUT_SECONDS = 180
MAX_RETRIES = 3
BACKOFF_BASE_SECONDS = 2.0
MAX_TOKENS_CAP = 2048
TRANSIENT_STATUS = frozenset({408, 429, 500, 502, 503, 504})


class TranslationClient(Protocol):
    def complete(self, prompt: str, max_tokens: int) -> str:
        """訳文 (strip 済み) を返す。接続不可は ServerUnreachable、他は ServerError。"""
        ...


def max_tokens_for(src: str) -> int:
    return min(MAX_TOKENS_CAP, len(src) * 3 + 128)


class _Transient(Exception):
    pass


class HttpClient:
    def __init__(
        self,
        base_url: str,
        *,
        sleep: Callable[[float], None] = time.sleep,
        timeout: float = TIMEOUT_SECONDS,
    ) -> None:
        self._endpoint = base_url.rstrip("/") + "/v1/completions"
        self._sleep = sleep
        self._timeout = timeout

    def complete(self, prompt: str, max_tokens: int) -> str:
        body = json.dumps(
            {
                "model": MODEL_NAME,
                "prompt": prompt,
                "temperature": 0,
                "max_tokens": max_tokens,
                "stop": STOP_SEQUENCES,
            }
        ).encode("utf-8")
        last: _Transient | None = None
        for attempt in range(MAX_RETRIES + 1):
            if attempt:
                self._sleep(BACKOFF_BASE_SECONDS * 2 ** (attempt - 1))
            try:
                return self._post(body)
            except _Transient as e:
                last = e
        raise ServerError(f"server kept failing after {MAX_RETRIES} retries: {last}")

    def _post(self, body: bytes) -> str:
        req = urllib.request.Request(
            self._endpoint, data=body, headers={"Content-Type": "application/json"}
        )
        try:
            with urllib.request.urlopen(req, timeout=self._timeout) as resp:
                payload = resp.read()
        except urllib.error.HTTPError as e:
            if e.code in TRANSIENT_STATUS:
                raise _Transient(f"HTTP {e.code}") from e
            raise ServerError(f"HTTP {e.code} from {self._endpoint}") from e
        except urllib.error.URLError as e:
            if isinstance(e.reason, (TimeoutError, socket.timeout)):
                raise _Transient("timeout") from e
            raise ServerUnreachable(f"cannot connect to {self._endpoint}: {e.reason}") from e
        except (TimeoutError, ConnectionError, OSError) as e:
            raise _Transient(str(e)) from e
        return _parse_response(payload)


def _parse_response(payload: bytes) -> str:
    try:
        text = json.loads(payload)["choices"][0]["text"]
    except (ValueError, KeyError, IndexError, TypeError) as e:
        raise ServerError(f"malformed completion response: {e}") from e
    if not isinstance(text, str):
        raise ServerError("malformed completion response: text is not a string")
    return text.strip()
