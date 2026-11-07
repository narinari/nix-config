import json

import pytest

from plamo_html.cli import main
from plamo_html.errors import ServerUnreachable

from helpers import FakeClient, MemoryCache

HTML = (
    "<!DOCTYPE html>\n<html lang='en'><head><title>Doc title</title><style>p{color:red}</style></head>"
    "<body><p id='a' class='c'>Hello <b>world</b> today</p></body></html>"
)


def _write(tmp_path):
    f = tmp_path / "in.html"
    f.write_text(HTML, encoding="utf-8")
    return f


def test_translate_writes_default_output(tmp_path, capsys):
    f = _write(tmp_path)
    client = FakeClient(lambda p: "<b1>世界</b1> こんにちは" if "Hello" in p.rsplit("<|plamo:msg|>", 2)[-2] else "題名")
    rc = main([str(f), "--no-cache"], client=client)
    out = (tmp_path / "in.ja.html").read_text(encoding="utf-8")
    assert rc == 0
    assert out.startswith("<!DOCTYPE html>") and '<html lang="ja">' in out
    assert '<p id="a" class="c"><b>世界</b> こんにちは</p>' in out
    assert "p{color:red}" in out
    err = capsys.readouterr().err
    assert "total=2 translated=2" in err and "2/2" in err


def test_output_equals_input_is_error(tmp_path):
    f = _write(tmp_path)
    assert main([str(f), "-o", str(f)], client=FakeClient(lambda p: "x")) == 1


def test_missing_input_and_bad_glossary_and_bad_args(tmp_path):
    assert main([str(tmp_path / "nope.html")], client=FakeClient(lambda p: "x")) == 1
    f = _write(tmp_path)
    g = tmp_path / "g.json"
    g.write_text("[1]")
    assert main([str(f), "--glossary", str(g)], client=FakeClient(lambda p: "x")) == 1
    with pytest.raises(SystemExit) as e:
        main([str(f), "--form", "weird"])
    assert e.value.code == 1


def test_unreachable_exit_code_2(tmp_path, capsys):
    f = _write(tmp_path)

    def down(_):
        raise ServerUnreachable("refused")

    rc = main([str(f), "--no-cache"], client=FakeClient(down))
    assert rc == 2
    assert "systemctl --user start plamo-llama-server" in capsys.readouterr().err
    assert not (tmp_path / "in.ja.html").exists()


def test_dry_run_does_not_call_client(tmp_path, capsys):
    f = _write(tmp_path)
    client = FakeClient(lambda p: pytest.fail("called"))
    assert main([str(f), "--dry-run"], client=client) == 0
    out = capsys.readouterr().out
    assert "blocks: 2" in out and "title: 1" in out and "english chars" in out


def test_failed_blocks_still_written_with_report(tmp_path, capsys):
    f = _write(tmp_path)
    rep = tmp_path / "r.json"
    rc = main([str(f), "--no-cache", "--report", str(rep)], client=FakeClient(lambda p: "english"), cache=None)
    assert rc == 0
    rows = json.loads(rep.read_text())
    assert len(rows) == 2 and "failed=2" in capsys.readouterr().err
    assert "Hello" in (tmp_path / "in.ja.html").read_text()


def test_env_url_used(monkeypatch, tmp_path):
    from plamo_html.cli import parse_options

    f = _write(tmp_path)
    monkeypatch.setenv("PLAMO_URL", "http://example:9")
    assert parse_options([str(f)]).url == "http://example:9"
    assert parse_options([str(f), "--url", "http://z"]).url == "http://z"
    monkeypatch.delenv("PLAMO_URL")
    assert parse_options([str(f)]).url == "http://127.0.0.1:8000"


def test_memory_cache_import_unused():
    assert MemoryCache().get("x") is None
