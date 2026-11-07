"""ドメイン型。lxml の要素を含むものは同一性比較 (eq=False) にする。"""

from __future__ import annotations

import enum
from dataclasses import dataclass, field
from typing import Mapping, NewType

from lxml import etree

Element = etree._Element
Item = str | Element
"""run を構成する要素。文字列、またはインライン要素 (tail は別の文字列として並ぶ)。"""

ProtectedText = NewType("ProtectedText", str)
"""プレースホルダ化済みで空白正規化済みの原文 (または訳文の比較基準)。"""

CacheKey = NewType("CacheKey", str)


class AtomKind(enum.Enum):
    CITATION = "citation"
    CONFIDENCE = "confidence"
    URL = "url"
    ELEMENT = "element"


@dataclass(frozen=True)
class LiteralSlot:
    """原子 <x{n}/> のうち、プレーンテキスト中の正規表現一致 (復元は文字列)。"""

    text: str
    kind: AtomKind


@dataclass(frozen=True, eq=False)
class ElementSlot:
    """元要素を保持するスロット。paired=True なら <b{n}>…</b{n}>、False なら <x{n}/>。"""

    element: Element
    paired: bool
    kind: AtomKind = AtomKind.ELEMENT


Slot = LiteralSlot | ElementSlot


@dataclass(frozen=True, eq=False)
class Protected:
    text: ProtectedText
    slots: Mapping[int, Slot]
    has_reserved: bool
    """原文がプレースホルダ形式や <|plamo: を既に含む (翻訳不可)。"""


class UnitKind(enum.Enum):
    BLOCK = "block"
    TITLE = "title"
    META = "meta"
    ATTR = "attr"


@dataclass(frozen=True)
class Run:
    items: tuple[Item, ...]


@dataclass(frozen=True, eq=False)
class Fixed:
    element: Element


Segment = Run | Fixed


@dataclass(eq=False)
class ParentPlan:
    """親要素の内容を run / 固定要素の列に分解したもの。抽出時に構築され、以後は読み取り専用。"""

    parent: Element
    segments: list[Segment] = field(default_factory=list)


@dataclass(frozen=True, eq=False)
class RunTarget:
    plan: ParentPlan
    segment: int


@dataclass(frozen=True, eq=False)
class TextTarget:
    element: Element


@dataclass(frozen=True, eq=False)
class AttrTarget:
    element: Element
    name: str


Target = RunTarget | TextTarget | AttrTarget


@dataclass(frozen=True, eq=False)
class Unit:
    index: int
    kind: UnitKind
    protected: Protected
    target: Target
