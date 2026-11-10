"""gdrive_setup: --auth-url で作った PKCE code_verifier / state が --auth-code に引き継がれる。"""

from __future__ import annotations

import json
import stat
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

pytest.importorskip("google_auth_oauthlib")

import src.gdrive_setup as setup  # noqa: E402

CLIENT = {
    "installed": {
        "client_id": "id.apps.googleusercontent.com",
        "client_secret": "secret",
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://oauth2.googleapis.com/token",
        "redirect_uris": ["http://localhost"],
    }
}


@pytest.fixture
def env(monkeypatch, tmp_path):
    hermes_home = tmp_path / "hermes"
    hermes_home.mkdir()
    (hermes_home / "google_client_secret.json").write_text(json.dumps(CLIENT))
    monkeypatch.setenv("HERMES_HOME", str(hermes_home))
    monkeypatch.setenv("GOLDPOINT_STATE_DIR", str(tmp_path / "state"))
    return tmp_path


def test_auth_url_persists_pkce_privately(env, capsys):
    assert setup.cmd_auth_url() == 0

    pending = env / "state" / setup.PENDING_FILENAME
    saved = json.loads(pending.read_text())
    assert saved["code_verifier"] and saved["state"]
    assert stat.S_IMODE(pending.stat().st_mode) == 0o600
    assert f"state={saved['state']}" in capsys.readouterr().out


def test_auth_code_reuses_saved_verifier(env, monkeypatch):
    setup.cmd_auth_url()
    saved = json.loads((env / "state" / setup.PENDING_FILENAME).read_text())
    seen = {}

    def fake_fetch_token(self, **kwargs):
        seen["verifier"] = self.code_verifier
        seen["state"] = self.oauth2session.state
        raise RuntimeError("stop before network")

    from google_auth_oauthlib.flow import Flow

    monkeypatch.setattr(Flow, "fetch_token", fake_fetch_token)
    with pytest.raises(RuntimeError, match="stop before network"):
        setup.cmd_auth_code("http://localhost:1/?code=x&state=" + saved["state"])

    assert seen == {"verifier": saved["code_verifier"], "state": saved["state"]}


def test_auth_code_without_pending_exits(env):
    with pytest.raises(SystemExit, match="--auth-url"):
        setup.cmd_auth_code("http://localhost:1/?code=x")
