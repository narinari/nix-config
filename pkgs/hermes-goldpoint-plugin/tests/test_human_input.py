"""human_input: CDP Input イベントの発行順序と、プロファイル置き場の扱い。"""

from __future__ import annotations

import asyncio
import random
import stat
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import src.cdp as cdp  # noqa: E402
import src.human_input as human_input  # noqa: E402


class FakeSession:
    def __init__(self, rect):
        self.rect = rect
        self.sent: list[tuple[str, dict]] = []

    async def send(self, method, params):
        self.sent.append((method, params))
        return {}

    async def eval_js(self, expression):
        return self.rect


@pytest.fixture(autouse=True)
def no_sleep(monkeypatch):
    async def instant(_):
        return None

    monkeypatch.setattr(human_input.asyncio, "sleep", instant)


def _run(coro):
    return asyncio.run(coro)


def test_type_text_sends_key_down_up_per_char():
    session = FakeSession(rect=None)
    human = human_input.HumanInput(session, rng=random.Random(0))

    _run(human.type_text("ab"))

    kinds = [(m, p["type"], p.get("text")) for m, p in session.sent]
    assert kinds == [
        ("Input.dispatchKeyEvent", "keyDown", "a"),
        ("Input.dispatchKeyEvent", "keyUp", None),
        ("Input.dispatchKeyEvent", "keyDown", "b"),
        ("Input.dispatchKeyEvent", "keyUp", None),
    ]


def test_click_moves_then_presses_inside_element():
    session = FakeSession(rect=[100, 50, 200, 40])
    human = human_input.HumanInput(session, rng=random.Random(1))

    _run(human.click_element("loginButton"))

    types = [p["type"] for _, p in session.sent]
    assert types[-2:] == ["mousePressed", "mouseReleased"]
    assert types.count("mouseMoved") >= human_input.MOUSE_STEPS_RANGE[0]
    press = session.sent[-2][1]
    assert 100 <= press["x"] <= 300 and 50 <= press["y"] <= 90


def test_click_invisible_element_raises():
    session = FakeSession(rect=None)
    human = human_input.HumanInput(session, rng=random.Random(2))

    with pytest.raises(human_input.InputError, match="not visible"):
        _run(human.click_element("missing"))


def test_persistent_profile_dir_is_private(tmp_path):
    target = tmp_path / "profile"

    path = cdp._prepare_profile_dir(target)

    assert path == target
    assert stat.S_IMODE(target.stat().st_mode) == 0o700


def test_persistent_profile_clears_stale_port_and_locks(tmp_path):
    target = tmp_path / "profile"
    target.mkdir()
    for name in cdp.STALE_PROFILE_FILES:
        (target / name).write_text("stale")
    (target / "Cookies").write_text("keep")

    cdp._prepare_profile_dir(target)

    assert not any((target / n).exists() for n in cdp.STALE_PROFILE_FILES)
    assert (target / "Cookies").read_text() == "keep"


def test_profile_survives_stop(monkeypatch, tmp_path):
    monkeypatch.setenv("GOLDPOINT_CHROMIUM_PROFILE", str(tmp_path / "profile"))
    proc = cdp.ChromiumProcess("chromium")
    proc._user_data_dir = cdp._prepare_profile_dir(proc._profile_dir)

    proc.stop()

    assert (tmp_path / "profile").is_dir()
