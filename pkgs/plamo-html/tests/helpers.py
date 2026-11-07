from __future__ import annotations

from typing import Callable

import lxml.html

from plamo_html.apply import apply_translations
from plamo_html.extract import extract_units
from plamo_html.pipeline import Settings, run_pipeline

SETTINGS = Settings(context="ctx", form="plain", glossary=(), history_chars=2000)


class FakeClient:
    """prompt を受け取り responder の返す文字列を返す。呼び出しを記録する。"""

    def __init__(self, responder: Callable[[str], str]) -> None:
        self.responder = responder
        self.prompts: list[str] = []

    def complete(self, prompt: str, max_tokens: int) -> str:
        self.prompts.append(prompt)
        return self.responder(prompt)


class MemoryCache:
    def __init__(self) -> None:
        self.data: dict[str, str] = {}

    def get(self, key):
        return self.data.get(key)

    def put(self, key, value):
        self.data[key] = value


def translate_html(html: str, responder, settings: Settings = SETTINGS, cache=None):
    root = lxml.html.document_fromstring(html)
    units = extract_units(root)
    client = FakeClient(responder)
    result = run_pipeline(units, client, cache or MemoryCache(), settings)
    apply_translations(units, result.restored)
    return root, units, result, client


def body_html(root) -> str:
    return lxml.html.tostring(root.find("body"), encoding="unicode")


def last_src(prompt: str) -> str:
    """プロンプト末尾の input から原文を取り出す。"""
    tail = prompt.rsplit("<|plamo:msg|>", 2)[-2]
    return tail.split("<|plamo:tag|>output")[0]


