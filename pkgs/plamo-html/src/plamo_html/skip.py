"""プレースホルダ化後のスキップ判定。"""

from __future__ import annotations

import enum
import re
from dataclasses import dataclass

from plamo_html.model import AtomKind, Protected
from plamo_html.tokens import TOKEN_RE

JAPANESE_CHAR_RE = re.compile(r"[぀-ヿ㐀-䶿一-鿿]")
LATIN_CHAR_RE = re.compile(r"[A-Za-z]")
WORD_RE = re.compile(r"(?<![\w/.-])[A-Za-z][a-z]{2,}(?![\w/.-])")
_LEADING_ATOM_RE = re.compile(r"^<x(\d+)/>")
_TRAILING_ATOM_RE = re.compile(r"<x(\d+)/>$")
JAPANESE_RATIO_THRESHOLD = 0.2


class SkipKind(enum.Enum):
    JAPANESE = "skipped_japanese"
    OTHER = "skipped_other"


@dataclass(frozen=True)
class Skip:
    kind: SkipKind
    reason: str


def plain_text(p: Protected) -> str:
    """タグ (プレースホルダ) を除いた本文。"""
    return TOKEN_RE.sub(" ", p.text)


def latin_char_count(p: Protected) -> int:
    return len(LATIN_CHAR_RE.findall(plain_text(p)))


def _atom_kind_at(p: Protected, pattern: re.Pattern[str]) -> AtomKind | None:
    m = pattern.search(p.text)
    if m is None:
        return None
    slot = p.slots.get(int(m.group(1)))
    if slot is None:
        return None
    return slot.kind


def _is_reference_line(p: Protected) -> bool:
    first = _atom_kind_at(p, _LEADING_ATOM_RE)
    last = _atom_kind_at(p, _TRAILING_ATOM_RE)
    return first is AtomKind.CITATION and last is AtomKind.URL


def classify(p: Protected) -> Skip | None:
    """翻訳不要ならその理由、翻訳対象なら None。"""
    if p.has_reserved:
        return Skip(SkipKind.OTHER, "source contains placeholder-like text")
    body = plain_text(p)
    ja = len(JAPANESE_CHAR_RE.findall(body))
    latin = len(LATIN_CHAR_RE.findall(body))
    if ja + latin > 0 and ja / (ja + latin) >= JAPANESE_RATIO_THRESHOLD:
        return Skip(SkipKind.JAPANESE, "already Japanese")
    if not WORD_RE.search(body):
        return Skip(SkipKind.OTHER, "no English words")
    if _is_reference_line(p):
        return Skip(SkipKind.OTHER, "bibliography line")
    return None



