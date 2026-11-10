"""CDP の Input ドメインで人の操作に近いクリック・キー入力を発生させる。

GOLD POINT CARD+ (Akamai) はページ上の JS でマウス・キーボードのイベントを収集しており、
`el.value = ...` で値を書き込むだけの送信は "Access Denied" になる (2026-11-10 確認)。
そのため実際の入力イベント (isTrusted=true) をランダムな間隔で発生させる。

セキュリティ: 入力文字列 (パスワード) はログにも例外メッセージにも出さない。
"""

from __future__ import annotations

import asyncio
import json
import random
from typing import Protocol

KEY_DELAY_RANGE_SECONDS = (0.07, 0.22)
MOUSE_STEPS_RANGE = (8, 18)
MOUSE_STEP_DELAY_RANGE_SECONDS = (0.008, 0.025)
CLICK_HOLD_RANGE_SECONDS = (0.05, 0.14)
ELEMENT_JITTER_RATIO = 0.25


class InputError(Exception):
    """要素の位置取得など入力操作の失敗。入力値は含めない。"""


class CdpSender(Protocol):
    async def send(self, method: str, params: dict) -> dict: ...

    async def eval_js(self, expression: str) -> object: ...


class HumanInput:
    """マウス位置を覚えておき、移動 → クリック → タイプを人間らしく行う。"""

    def __init__(self, session: CdpSender, rng: random.Random | None = None) -> None:
        self._session = session
        self._rng = rng or random.Random()
        self._x = self._rng.uniform(200, 600)
        self._y = self._rng.uniform(150, 400)

    async def pause(self, low: float, high: float) -> None:
        await asyncio.sleep(self._rng.uniform(low, high))

    async def click_element(self, element_id: str) -> None:
        x, y = await self._element_point(element_id)
        await self._move_to(x, y)
        await self._mouse("mousePressed", x, y)
        await self.pause(*CLICK_HOLD_RANGE_SECONDS)
        await self._mouse("mouseReleased", x, y)

    async def type_text(self, text: str) -> None:
        for char in text:
            await self._session.send("Input.dispatchKeyEvent", {"type": "keyDown", "text": char})
            await self._session.send("Input.dispatchKeyEvent", {"type": "keyUp"})
            await self.pause(*KEY_DELAY_RANGE_SECONDS)

    async def _element_point(self, element_id: str) -> tuple[float, float]:
        expr = (
            "(() => {"
            f"const el = document.getElementById({json.dumps(element_id)});"
            "if (!el) return null;"
            "el.scrollIntoView({block: 'center'});"
            "const r = el.getBoundingClientRect();"
            "return [r.left, r.top, r.width, r.height];"
            "})()"
        )
        rect = await self._session.eval_js(expr)
        if not isinstance(rect, list) or len(rect) != 4 or rect[2] <= 0 or rect[3] <= 0:
            raise InputError(f"element not visible: {element_id}")
        left, top, width, height = (float(v) for v in rect)
        jitter = ELEMENT_JITTER_RATIO
        x = left + width * self._rng.uniform(0.5 - jitter, 0.5 + jitter)
        y = top + height * self._rng.uniform(0.5 - jitter, 0.5 + jitter)
        return x, y

    async def _move_to(self, x: float, y: float) -> None:
        steps = self._rng.randint(*MOUSE_STEPS_RANGE)
        start_x, start_y = self._x, self._y
        for i in range(1, steps + 1):
            t = i / steps
            eased = t * t * (3 - 2 * t)  # smoothstep で加減速
            px = start_x + (x - start_x) * eased + self._rng.uniform(-1.5, 1.5)
            py = start_y + (y - start_y) * eased + self._rng.uniform(-1.5, 1.5)
            await self._mouse("mouseMoved", px, py)
            await self.pause(*MOUSE_STEP_DELAY_RANGE_SECONDS)
        await self._mouse("mouseMoved", x, y)
        self._x, self._y = x, y

    async def _mouse(self, kind: str, x: float, y: float) -> None:
        params: dict = {"type": kind, "x": x, "y": y}
        if kind in ("mousePressed", "mouseReleased"):
            params.update(button="left", clickCount=1)
        await self._session.send("Input.dispatchMouseEvent", params)
