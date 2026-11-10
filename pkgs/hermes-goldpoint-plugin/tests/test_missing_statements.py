"""handlers.fetch_missing_statements / goldpoint.parse_available_months のテスト。"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import src.bw as bw  # noqa: E402
import src.goldpoint as goldpoint  # noqa: E402
import src.gdrive as gdrive  # noqa: E402
import src.handlers as handlers  # noqa: E402


@pytest.fixture
def env(tmp_path, monkeypatch):
    monkeypatch.setenv("GOLDPOINT_STATE_DIR", str(tmp_path))
    monkeypatch.setenv("GOLDPOINT_BW_ITEM_ID", "item")
    monkeypatch.setattr(bw, "get_login", lambda _id: _cred())
    monkeypatch.setattr(gdrive, "ensure_folder_path", lambda _p: "folder")
    state = {"uploads": [], "fail_on": None, "asked": None, "available": []}

    def fake_fetch(*, auth_key, password, current_seikyuym, wanted):
        state["asked"] = wanted(state["available"])
        return {m: state["results"].get(m) for m in state["asked"]}

    def fake_upload(*, folder_id, filename, content, mimetype):
        if filename == state["fail_on"]:
            raise gdrive.GDriveError("boom")
        state["uploads"].append(filename)
        return {"id": "x", "name": filename}

    monkeypatch.setattr(goldpoint, "fetch_statements_csv", fake_fetch)
    monkeypatch.setattr(gdrive, "upload_or_replace", fake_upload)
    state["results"] = {}
    state["tmp"] = tmp_path
    return state


def _cred():
    return type("C", (), {"username": "u", "password": "p"})()


def test_wanted_excludes_local_months(env):
    (env["tmp"] / "csv").mkdir()
    (env["tmp"] / "csv" / "2026-09.csv").write_bytes(b"old")
    (env["tmp"] / "uploaded.txt").write_text("2026-09.csv\n")
    env["available"] = ["202609", "202610"]
    env["results"] = {"202610": b"new"}
    result = handlers.fetch_missing_statements()
    assert env["asked"] == ["202610"]
    assert result["fetched"] == ["202610"]
    assert result["uploaded"] == ["2026-10.csv"]


def test_not_ready_months_skipped_and_not_saved(env):
    env["available"] = ["202610", "202611"]
    env["results"] = {"202610": b"a", "202611": None}
    result = handlers.fetch_missing_statements()
    assert result["skipped_not_ready"] == ["202611"]
    assert not (env["tmp"] / "csv" / "2026-11.csv").exists()
    assert (env["tmp"] / "csv" / "2026-10.csv").read_bytes() == b"a"


def test_only_unlisted_files_uploaded_and_marker_updated(env):
    csv = env["tmp"] / "csv"
    csv.mkdir()
    (csv / "2026-08.csv").write_bytes(b"x")
    (csv / "2026-09.csv").write_bytes(b"y")
    (env["tmp"] / "uploaded.txt").write_text("2026-08.csv\n")
    result = handlers.fetch_missing_statements()
    assert env["uploads"] == ["2026-09.csv"]
    assert result["pending_upload"] == []
    assert (env["tmp"] / "uploaded.txt").read_text().split() == [
        "2026-08.csv",
        "2026-09.csv",
    ]


def test_gdrive_error_midway_keeps_fetched(env):
    env["available"] = ["202608", "202609", "202610"]
    env["results"] = {m: b"d" for m in env["available"]}
    env["fail_on"] = "2026-09.csv"
    result = handlers.fetch_missing_statements()
    assert result["fetched"] == ["202608", "202609", "202610"]
    assert result["uploaded"] == ["2026-08.csv"]
    assert result["pending_upload"] == ["2026-09.csv", "2026-10.csv"]
    assert "upload_error" in result and "hint" in result
    assert "error" not in result


def test_nothing_new(env):
    result = handlers.fetch_missing_statements()
    assert result["fetched"] == []
    assert result["skipped_not_ready"] == []
    assert result["uploaded"] == []
    assert result["pending_upload"] == []
    assert "error" not in result and "upload_error" not in result


def test_parse_available_months_filters_dedupes_sorts():
    raw = ["202610", "", "abc", "202608", "202610", None, "20260", 202609]
    assert goldpoint.parse_available_months(raw) == ["202608", "202610"]
