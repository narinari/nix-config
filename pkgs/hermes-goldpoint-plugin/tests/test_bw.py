"""bw.py / config.bw_item_id のユニットテスト (subprocess はモック)。"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import src.bw as bw  # noqa: E402
import src.config as cfg  # noqa: E402

SESSION = "SESSIONKEY-xyz-123"
MASTER = "MASTER-pw-456"
USER = "user-789"
PASSWORD = "login-pw-abc"
SECRETS = (SESSION, MASTER, PASSWORD, USER)


def _cp(rc=0, out="", err=""):
    return subprocess.CompletedProcess([], rc, stdout=out, stderr=err)


def _item(login=None):
    return json.dumps({"login": login if login is not None else {"username": USER, "password": PASSWORD}})


@pytest.fixture
def pwfile(tmp_path, monkeypatch):
    f = tmp_path / "pw"
    f.write_text(MASTER)
    monkeypatch.setenv(bw.ENV_PASSWORD_FILE, str(f))
    monkeypatch.setenv("PATH", "/usr/bin")
    monkeypatch.setenv("UNRELATED_SECRET", "leak-me")
    return f


@pytest.fixture
def calls(monkeypatch):
    recorded = []

    def install(handler):
        def fake_run(cmd, **kw):
            recorded.append((cmd, kw))
            return handler(cmd, kw)

        monkeypatch.setattr(bw.subprocess, "run", fake_run)
        return recorded

    return install


def _ok_handler(cmd, kw):
    if cmd[1] == "unlock":
        return _cp(out=SESSION + "\n")
    if cmd[1] == "sync":
        return _cp(out="Syncing complete.")
    return _cp(out=_item())


def _assert_no_secret(texts):
    for t in texts:
        for s in SECRETS:
            assert s not in t


def test_success_returns_credential_and_scopes_session(pwfile, calls):
    rec = calls(_ok_handler)
    before = dict(os.environ)
    cred = bw.get_login("item-1")
    assert (cred.username, cred.password) == (USER, PASSWORD)
    assert dict(os.environ) == before
    assert "BW_SESSION" not in os.environ
    by_cmd = {c[1]: kw for c, kw in rec}
    assert "BW_SESSION" not in by_cmd["unlock"]["env"]
    assert by_cmd["sync"]["env"]["BW_SESSION"] == SESSION
    assert by_cmd["get"]["env"]["BW_SESSION"] == SESSION
    assert "UNRELATED_SECRET" not in by_cmd["get"]["env"]
    assert by_cmd["get"]["env"]["NO_COLOR"] == "1"
    assert all(kw["stdin"] == subprocess.DEVNULL for _, kw in rec)
    assert not any(c[1] == "lock" for c, _ in rec)
    assert SESSION not in repr(cred) and PASSWORD not in repr(cred)


def test_sync_failure_is_warning_and_continues(pwfile, calls, caplog):
    def h(cmd, kw):
        return _cp(rc=1, err="boom " + SESSION) if cmd[1] == "sync" else _ok_handler(cmd, kw)

    calls(h)
    with caplog.at_level(logging.DEBUG):
        assert bw.get_login("i").password == PASSWORD
    assert any(r.levelno == logging.WARNING for r in caplog.records)
    _assert_no_secret([r.getMessage() for r in caplog.records])


def test_unlock_failure(pwfile, calls, caplog):
    calls(lambda c, k: _cp(rc=1, out=SESSION, err="bad " + MASTER))
    with caplog.at_level(logging.DEBUG), pytest.raises(bw.BwError) as ei:
        bw.get_login("i")
    assert "exit code 1" in str(ei.value)
    _assert_no_secret([str(ei.value), caplog.text])


def test_unlock_empty_output(pwfile, calls):
    calls(lambda c, k: _cp(out="  \n"))
    with pytest.raises(bw.BwError):
        bw.get_login("i")


def test_not_logged_in(pwfile, calls):
    calls(lambda c, k: _cp(rc=1, err="You are Not Logged In."))
    with pytest.raises(bw.BwError, match="hermes-bw-login"):
        bw.get_login("i")


def test_missing_password_file(monkeypatch, tmp_path):
    monkeypatch.setenv(bw.ENV_PASSWORD_FILE, str(tmp_path / "nope"))
    with pytest.raises(bw.BwError, match="missing or unreadable"):
        bw.get_login("i")


def test_unset_password_env(monkeypatch):
    monkeypatch.delenv(bw.ENV_PASSWORD_FILE, raising=False)
    with pytest.raises(bw.BwError, match=bw.ENV_PASSWORD_FILE):
        bw.get_login("i")


def test_empty_item_id(pwfile):
    with pytest.raises(bw.BwError):
        bw.get_login("")


def test_bad_json(pwfile, calls):
    def h(cmd, kw):
        return _cp(out="not json " + PASSWORD) if cmd[1] == "get" else _ok_handler(cmd, kw)

    calls(h)
    with pytest.raises(bw.BwError) as ei:
        bw.get_login("i")
    _assert_no_secret([str(ei.value)])


@pytest.mark.parametrize(
    "login",
    [{"username": USER}, {"username": USER, "password": ""}, {"username": USER, "password": 5}, {}, "x"],
)
def test_missing_login_fields(pwfile, calls, login):
    def h(cmd, kw):
        return _cp(out=_item(login)) if cmd[1] == "get" else _ok_handler(cmd, kw)

    calls(h)
    with pytest.raises(bw.BwError, match="no login username/password") as ei:
        bw.get_login("i")
    _assert_no_secret([str(ei.value)])


def test_get_failure(pwfile, calls):
    def h(cmd, kw):
        return _cp(rc=2, err=PASSWORD) if cmd[1] == "get" else _ok_handler(cmd, kw)

    calls(h)
    with pytest.raises(bw.BwError) as ei:
        bw.get_login("i")
    _assert_no_secret([str(ei.value)])


def test_timeout(pwfile, calls):
    def h(cmd, kw):
        raise subprocess.TimeoutExpired(cmd, 60, output=SESSION)

    calls(h)
    with pytest.raises(bw.BwError, match="60s") as ei:
        bw.get_login("i")
    _assert_no_secret([str(ei.value)])


def test_binary_missing(pwfile, calls):
    def h(cmd, kw):
        raise FileNotFoundError("bw")

    calls(h)
    with pytest.raises(bw.BwError, match="not found"):
        bw.get_login("i")


def test_config_bw_item_id(monkeypatch):
    monkeypatch.delenv(cfg.ENV_BW_ITEM_ID, raising=False)
    assert cfg.bw_item_id() is None
    monkeypatch.setenv(cfg.ENV_BW_ITEM_ID, "  abc-123 \n")
    assert cfg.bw_item_id() == "abc-123"
    assert cfg.snapshot().bw_item_id_configured is True
    monkeypatch.setenv(cfg.ENV_BW_ITEM_ID, "  ")
    assert cfg.bw_item_id() is None
