"""訳文の検証。"""

from __future__ import annotations

import re
from dataclasses import dataclass

from plamo_html.model import Protected
from plamo_html.skip import WORD_RE
from plamo_html.tokens import (
    TOKEN_RE,
    Token,
    is_well_nested,
    marker_multiset,
    tokenize,
)

JAPANESE_RE = re.compile(r"[぀-ヿ㐀-䶿一-鿿]")
MAX_LENGTH_RATIO = 4
MAX_ECHOED_NAME_WORDS = 2


@dataclass(frozen=True)
class Valid:
    tokens: tuple[Token, ...]


@dataclass(frozen=True)
class Invalid:
    reason: str
    output: str | None = None


def _is_echoed_name(source: Protected, dst: str) -> bool:
    """固有名だけの文は訳さず原文のまま返るのが正しい。"""
    is_identical = dst == source.text.strip()
    return is_identical and len(WORD_RE.findall(TOKEN_RE.sub(" ", dst))) <= MAX_ECHOED_NAME_WORDS


def check_translation(source: Protected, output: str) -> Valid | Invalid:
    dst = output.strip()
    if not dst:
        return Invalid("empty output", output)
    src_tokens = tokenize(source.text)
    dst_tokens = tokenize(dst)
    want, got = marker_multiset(src_tokens), marker_multiset(dst_tokens)
    if want != got:
        missing = sorted(str(k) for k in (want - got))
        extra = sorted(str(k) for k in (got - want))
        return Invalid(f"placeholder mismatch (missing={missing}, extra={extra})", output)
    if not is_well_nested(dst_tokens):
        return Invalid("paired placeholders are not properly nested", output)
    if not JAPANESE_RE.search(dst) and not _is_echoed_name(source, dst):
        return Invalid("output contains no Japanese", output)
    if len(dst) > MAX_LENGTH_RATIO * len(source.text):
        return Invalid("output is more than 4x longer than source", output)
    return Valid(dst_tokens)
