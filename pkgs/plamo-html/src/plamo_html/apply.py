"""翻訳結果を木に書き戻す。"""

from __future__ import annotations

from typing import Mapping

from plamo_html.inline import append_items
from plamo_html.model import (
    AttrTarget,
    Fixed,
    Item,
    ParentPlan,
    RunTarget,
    TextTarget,
    Unit,
)


def _plain(items: tuple[Item, ...]) -> str:
    return "".join(i for i in items if isinstance(i, str))


def _rebuild(plan: ParentPlan, replacements: Mapping[int, tuple[Item, ...]]) -> None:
    parent = plan.parent
    for child in list(parent):
        child.tail = None
        parent.remove(child)
    parent.text = None
    for i, seg in enumerate(plan.segments):
        if isinstance(seg, Fixed):
            append_items(parent, [seg.element])
        else:
            append_items(parent, replacements.get(i, seg.items))


def apply_translations(units: tuple[Unit, ...], restored: Mapping[int, tuple[Item, ...]]) -> None:
    """restored は Unit.index -> 復元済み要素列。翻訳できなかった単位は原文のまま残る。"""
    by_plan: dict[int, tuple[ParentPlan, dict[int, tuple[Item, ...]]]] = {}
    for unit in units:
        items = restored.get(unit.index)
        if items is None:
            continue
        target = unit.target
        if isinstance(target, RunTarget):
            _, repl = by_plan.setdefault(id(target.plan), (target.plan, {}))
            repl[target.segment] = items
        elif isinstance(target, TextTarget):
            target.element.text = _plain(items)
        elif isinstance(target, AttrTarget):
            target.element.set(target.name, _plain(items))
    for plan, repl in by_plan.values():
        _rebuild(plan, repl)


