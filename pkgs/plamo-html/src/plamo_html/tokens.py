"""訳文のトークン化。HTML パーサは使わず、プレースホルダ形式だけを切り出す。"""

from __future__ import annotations

import re
from collections import Counter
from dataclasses import dataclass

TOKEN_RE = re.compile(r"</?b\d+>|<x\d+/>")
RESERVED_RE = re.compile(r"</?b\d+>|<x\d+/>|<\|plamo:")


@dataclass(frozen=True)
class Text:
    value: str


@dataclass(frozen=True)
class Open:
    n: int


@dataclass(frozen=True)
class Close:
    n: int


@dataclass(frozen=True)
class Atom:
    n: int


Token = Text | Open | Close | Atom


def _parse_marker(marker: str) -> Token:
    if marker.startswith("</"):
        return Close(int(marker[3:-1]))
    if marker.startswith("<b"):
        return Open(int(marker[2:-1]))
    return Atom(int(marker[2:-2]))


def tokenize(text: str) -> tuple[Token, ...]:
    out: list[Token] = []
    pos = 0
    for m in TOKEN_RE.finditer(text):
        if m.start() > pos:
            out.append(Text(text[pos : m.start()]))
        out.append(_parse_marker(m.group()))
        pos = m.end()
    if pos < len(text):
        out.append(Text(text[pos:]))
    return tuple(out)


def marker_multiset(tokens: tuple[Token, ...]) -> Counter[Token]:
    return Counter(t for t in tokens if not isinstance(t, Text))


def is_well_nested(tokens: tuple[Token, ...]) -> bool:
    stack: list[int] = []
    for t in tokens:
        if isinstance(t, Open):
            stack.append(t.n)
        elif isinstance(t, Close):
            if not stack or stack.pop() != t.n:
                return False
    return not stack
