"""cdp._user_agent: HeadlessChrome を含まない通常 Chrome 相当の UA を組み立てる。"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import src.cdp as cdp  # noqa: E402


def _fake_run(stdout: str, returncode: int = 0):
    def run(args, **kwargs):
        assert args[1] == "--version"
        return subprocess.CompletedProcess(args, returncode, stdout=stdout, stderr="")

    return run


def test_builds_chrome_ua_from_major_version(monkeypatch):
    monkeypatch.setattr(
        cdp.subprocess, "run", _fake_run("Chromium 157.0.8103.38 built on NixOS\n")
    )

    ua = cdp._user_agent("/nix/store/x/bin/chromium")

    assert "Chrome/157.0.0.0" in ua
    assert "Headless" not in ua


def test_unparsable_version_raises(monkeypatch):
    monkeypatch.setattr(cdp.subprocess, "run", _fake_run("garbage"))

    with pytest.raises(cdp.CdpError, match="could not parse"):
        cdp._user_agent("chromium")


def test_nonzero_exit_raises(monkeypatch):
    monkeypatch.setattr(cdp.subprocess, "run", _fake_run("Chromium 157.0.1.2", 1))

    with pytest.raises(cdp.CdpError):
        cdp._user_agent("chromium")


def test_missing_binary_raises(monkeypatch):
    def run(args, **kwargs):
        raise FileNotFoundError(args[0])

    monkeypatch.setattr(cdp.subprocess, "run", run)

    with pytest.raises(cdp.CdpError, match="failed to query"):
        cdp._user_agent("nope")
