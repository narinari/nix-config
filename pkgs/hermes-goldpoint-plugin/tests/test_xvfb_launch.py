"""Xvfb の起動・停止と、ChromiumProcess の起動引数 (headed / headless)。"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import src.cdp as cdp  # noqa: E402
import src.xvfb as xvfb  # noqa: E402


@pytest.mark.skipif(shutil.which("Xvfb") is None, reason="Xvfb not installed")
def test_virtual_display_starts_and_stops():
    display = xvfb.VirtualDisplay("Xvfb")

    value = display.start()
    try:
        assert value.startswith(":")
        assert value[1:].isdigit()
    finally:
        display.stop()

    assert display._proc is None


def test_missing_xvfb_binary_raises():
    with pytest.raises(xvfb.XvfbError, match="not found"):
        xvfb.VirtualDisplay("/nonexistent/Xvfb").start()


def test_headed_launch_uses_virtual_display(monkeypatch, tmp_path):
    monkeypatch.delenv("GOLDPOINT_HEADLESS", raising=False)
    monkeypatch.setenv("WAYLAND_DISPLAY", "wayland-1")
    monkeypatch.setattr(xvfb.VirtualDisplay, "start", lambda self: ":42")
    proc = cdp.ChromiumProcess("chromium")
    proc._user_data_dir = tmp_path

    args, env = proc._launch_spec("chromium")

    assert env["DISPLAY"] == ":42"
    assert "WAYLAND_DISPLAY" not in env
    assert not any(a.startswith("--headless") for a in args)
    assert "--ozone-platform=x11" in args


def test_headless_launch_skips_xvfb(monkeypatch, tmp_path):
    monkeypatch.setenv("GOLDPOINT_HEADLESS", "1")
    monkeypatch.setattr(cdp, "_user_agent", lambda binary: "UA")

    def fail_start(self):
        raise AssertionError("Xvfb must not start in headless mode")

    monkeypatch.setattr(xvfb.VirtualDisplay, "start", fail_start)
    proc = cdp.ChromiumProcess("chromium")
    proc._user_data_dir = tmp_path

    args, _ = proc._launch_spec("chromium")

    assert "--headless=new" in args
    assert "--user-agent=UA" in args
