"""インライン保護 (原文 -> プレースホルダ付きテキスト) と復元 (訳文トークン -> 要素列)。"""

from __future__ import annotations

import re
from typing import Sequence

from plamo_html.model import (
    AtomKind,
    Element,
    ElementSlot,
    Item,
    LiteralSlot,
    Protected,
    ProtectedText,
    Slot,
)
from plamo_html.tokens import RESERVED_RE, Atom, Close, Open, Text, Token

EXCLUDED_TAGS = frozenset({"pre", "code", "script", "style", "svg", "math", "textarea"})
INLINE_TAGS = frozenset(
    "a strong em b i span code kbd samp var sub sup abbr mark small u s cite q time br img".split()
)
ATOM_TAGS = frozenset({"code", "kbd", "samp", "var", "br", "img"})

_LITERAL_RE = re.compile(
    r"(?P<citation>\[[^\[\]]{1,80}, \d{4}[a-z]?\])"
    r"|(?P<confidence>\[(?:confidence|disputed|UNVERIFIED)[^\]]*\])"
    r"|(?P<url>https?://[^\s<>)\]]+)"
)
_LITERAL_KINDS = {
    "citation": AtomKind.CITATION,
    "confidence": AtomKind.CONFIDENCE,
    "url": AtomKind.URL,
}
_SPACES_RE = re.compile(r"\s+")


def is_excluded(el: Element) -> bool:
    if not isinstance(el.tag, str):
        return False
    if el.tag in EXCLUDED_TAGS or el.get("translate") == "no":
        return True
    return "notranslate" in (el.get("class") or "").split()


def _atom_kind(el: Element) -> AtomKind | None:
    """要素が原子ならその種別、ペア対象なら None。"""
    if not isinstance(el.tag, str) or is_excluded(el) or el.tag in ATOM_TAGS:
        return AtomKind.ELEMENT
    text = el.text_content().strip()
    if not text:
        return AtomKind.ELEMENT
    href = (el.get("href") or "").strip()
    if el.tag == "a" and href == text:
        return AtomKind.URL
    return None


class _Builder:
    def __init__(self) -> None:
        self.parts: list[str] = []
        self.slots: dict[int, Slot] = {}
        self.counter = 0
        self.reserved = False

    def new_id(self) -> int:
        self.counter += 1
        return self.counter

    def add_text(self, s: str) -> None:
        if RESERVED_RE.search(s):
            self.reserved = True
        pos = 0
        for m in _LITERAL_RE.finditer(s):
            self.parts.append(s[pos : m.start()])
            n = self.new_id()
            kind = _LITERAL_KINDS[m.lastgroup or "url"]
            self.slots[n] = LiteralSlot(m.group(), kind)
            self.parts.append(f"<x{n}/>")
            pos = m.end()
        self.parts.append(s[pos:])

    def add_element(self, el: Element) -> None:
        kind = _atom_kind(el)
        n = self.new_id()
        if kind is not None:
            self.slots[n] = ElementSlot(el, paired=False, kind=kind)
            self.parts.append(f"<x{n}/>")
            return
        self.slots[n] = ElementSlot(el, paired=True)
        self.parts.append(f"<b{n}>")
        if el.text:
            self.add_text(el.text)
        for child in el:
            self.add_element(child)
            if child.tail:
                self.add_text(child.tail)
        self.parts.append(f"</b{n}>")

    def build(self) -> Protected:
        text = _SPACES_RE.sub(" ", "".join(self.parts)).strip()
        return Protected(ProtectedText(text), self.slots, self.reserved)


def protect_items(items: Sequence[Item]) -> Protected:
    b = _Builder()
    for item in items:
        if isinstance(item, str):
            b.add_text(item)
        else:
            b.add_element(item)
    return b.build()


def protect_text(s: str) -> Protected:
    return protect_items([s])


def append_items(el: Element, items: Sequence[Item]) -> None:
    """el の末尾に items を追加する (文字列は text / tail に連結)。"""
    last: Element | None = el[-1] if len(el) else None
    for item in items:
        if isinstance(item, str):
            if last is None:
                el.text = (el.text or "") + item
            else:
                last.tail = (last.tail or "") + item
        else:
            item.tail = None
            el.append(item)
            last = item


def _reset(el: Element) -> None:
    el.text = None
    for child in list(el):
        child.tail = None
        el.remove(child)


def _slot_item(slot: Slot) -> Item:
    if isinstance(slot, LiteralSlot):
        return slot.text
    slot.element.tail = None
    return slot.element


def restore(protected: Protected, tokens: tuple[Token, ...]) -> tuple[Item, ...]:
    """検証済みトークン列から要素列を復元する (元要素を再利用する)。"""
    stack: list[tuple[int, list[Item]]] = [(0, [])]
    for t in tokens:
        if isinstance(t, Text):
            stack[-1][1].append(t.value)
        elif isinstance(t, Atom):
            stack[-1][1].append(_slot_item(protected.slots[t.n]))
        elif isinstance(t, Open):
            stack.append((t.n, []))
        elif isinstance(t, Close):
            n, items = stack.pop()
            slot = protected.slots[n]
            assert isinstance(slot, ElementSlot)
            _reset(slot.element)
            append_items(slot.element, items)
            stack[-1][1].append(slot.element)
    return tuple(stack[0][1])
