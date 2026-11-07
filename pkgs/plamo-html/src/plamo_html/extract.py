"""lxml.html の木から翻訳単位 (Unit) を文書順に抽出する。"""

from __future__ import annotations

from typing import Iterator

from plamo_html.inline import INLINE_TAGS, is_excluded, protect_items, protect_text
from plamo_html.model import (
    AttrTarget,
    Element,
    Fixed,
    Item,
    ParentPlan,
    Protected,
    Run,
    RunTarget,
    Target,
    TextTarget,
    Unit,
    UnitKind,
)

TRANSLATABLE_ATTRS = ("alt", "title", "aria-label", "placeholder")


def _inline_tree_ok(el: Element) -> bool:
    for child in el:
        if not isinstance(child.tag, str) or is_excluded(child):
            continue
        if child.tag not in INLINE_TAGS or not _inline_tree_ok(child):
            return False
    return True


def _is_run_member(el: Element) -> bool:
    if not isinstance(el.tag, str) or el.tag not in INLINE_TAGS:
        return False
    return is_excluded(el) or _inline_tree_ok(el)


class _Collector:
    def __init__(self) -> None:
        self.units: list[Unit] = []

    def add(self, kind: UnitKind, protected: Protected, target: Target) -> None:
        if protected.text:
            self.units.append(Unit(len(self.units), kind, protected, target))

    def flush_run(self, plan: ParentPlan, items: list[Item]) -> None:
        if not items:
            return
        plan.segments.append(Run(tuple(items)))
        self.add(UnitKind.BLOCK, protect_items(items), RunTarget(plan, len(plan.segments) - 1))

    def walk_container(self, el: Element) -> None:
        plan = ParentPlan(el)
        items: list[Item] = [el.text] if el.text else []
        for child in el:
            if _is_run_member(child):
                items.append(child)
            else:
                self.flush_run(plan, items)
                items = []
                plan.segments.append(Fixed(child))
                if isinstance(child.tag, str) and not is_excluded(child):
                    self.walk_container(child)
            if child.tail:
                items.append(child.tail)
        self.flush_run(plan, items)


def _translatable_elements(el: Element) -> Iterator[Element]:
    if not isinstance(el.tag, str) or is_excluded(el):
        return
    yield el
    for child in el:
        yield from _translatable_elements(child)


def _head_units(root: Element, out: _Collector) -> None:
    for title in root.xpath("//head/title"):
        text = "".join(title.itertext())
        out.add(UnitKind.TITLE, protect_text(text), TextTarget(title))
    for meta in root.xpath("//head/meta"):
        if (meta.get("name") or "").lower() == "description" and meta.get("content"):
            out.add(UnitKind.META, protect_text(meta.get("content")), AttrTarget(meta, "content"))


def _attr_units(body: Element, out: _Collector) -> None:
    for el in _translatable_elements(body):
        for name in TRANSLATABLE_ATTRS:
            value = el.get(name)
            if value:
                out.add(UnitKind.ATTR, protect_text(value), AttrTarget(el, name))


def extract_units(root: Element) -> tuple[Unit, ...]:
    """title / meta description、本文の run、属性の順に Unit を返す。"""
    out = _Collector()
    _head_units(root, out)
    body = root.find("body")
    if body is not None:
        out.walk_container(body)
        _attr_units(body, out)
    return tuple(out.units)
