import json

import lxml.html

from plamo_html.cache import FileCache, make_key
from plamo_html.pipeline import History, Settings
from plamo_html.prompt import Pair

from helpers import MemoryCache, SETTINGS, body_html, last_src, translate_html

HTML = "<html><body><p>First sentence here</p><p>Second sentence here</p><p>Third sentence here</p></body></html>"


def test_missing_token_retries_without_history_then_fails():
    html = "<html><body><p>One sentence</p><p>Two <b>sentence</b> here</p></body></html>"
    calls = []

    def responder(prompt):
        calls.append(prompt)
        return "一つ目" if "One" in last_src(prompt) else "二つ目 (タグ欠落)"

    root, _, result, client = translate_html(html, responder)
    assert result.stats.translated == 1 and result.stats.failed == 1
    assert "Two <b>sentence</b> here" in body_html(root)
    assert "placeholder mismatch" in result.failures[0].reason
    # 2 件目は履歴あり -> 履歴なしの 2 回
    assert len(client.prompts) == 3
    assert "One sentence" in client.prompts[1] and "One sentence" not in client.prompts[2].split("Two")[0]


def test_history_is_truncated_oldest_first():
    h = History(limit=30)
    h = h.push(Pair("a" * 10, "b" * 10)).push(Pair("c" * 5, "d" * 5))
    assert [p.src[0] for p in h.pairs] == ["a", "c"]
    h = h.push(Pair("e" * 5, "f" * 5))
    assert [p.src[0] for p in h.pairs] == ["c", "e"]
    assert History(limit=5).push(Pair("aaaa", "bbbb")).pairs == ()


def test_history_is_in_prompt_and_cache_hits_feed_history():
    cache = MemoryCache()
    settings = Settings("ctx", "plain", (), 2000)
    key = make_key("ctx", "plain", (), "First sentence here")
    cache.put(key, "最初の文")
    _, _, result, client = translate_html(HTML, lambda p: "訳文です", settings, cache)
    assert result.stats.cached == 1 and result.stats.translated == 2
    assert "最初の文" in client.prompts[0]


def test_duplicate_units_resolved_by_cache():
    html = "<html><body><p>Same sentence</p><p>Same sentence</p></body></html>"
    _, _, result, client = translate_html(html, lambda p: "同じ文")
    assert len(client.prompts) == 1
    assert result.stats.translated == 1 and result.stats.cached == 1


def test_file_cache_resume(tmp_path):
    path = tmp_path / "c" / "cache.jsonl"
    c1 = FileCache(path)
    c1.put("k1", "訳1")
    with path.open("a") as f:
        f.write('{"k": "broken')  # 途中停止
    c2 = FileCache(path)
    assert c2.get("k1") == "訳1"
    c2.put("k2", "訳2")
    c3 = FileCache(path)
    assert c3.get("k2") == "訳2" and c3.get("k1") == "訳1"


def test_title_meta_and_attributes_translated():
    html = (
        "<html><head><title>Big title</title><meta name='description' content='Some description'></head>"
        "<body><img alt='A chart image' src='x.png'><p>Body text <a title='Link title here' href='#a'>link</a></p></body></html>"
    )
    root, _, result, _ = translate_html(html, lambda p: "日本語")
    out = lxml.html.tostring(root, encoding="unicode")
    assert "<title>日本語</title>" in out
    assert 'content="日本語"' in out and 'alt="日本語"' in out and 'title="日本語"' in out
    assert 'href="#a"' in out


def test_excluded_content_untouched():
    html = "<html><body><pre>keep this text</pre><p class='notranslate'>Do not touch</p><script>var a = 'English words';</script><p>Translate me</p></body></html>"
    root, units, _, _ = translate_html(html, lambda p: "訳")
    assert len(units) == 1
    assert "keep this text" in body_html(root) and "Do not touch" in body_html(root)


def test_server_error_marks_failed():
    from plamo_html.errors import ServerError

    def boom(_):
        raise ServerError("HTTP 400")

    _, _, result, _ = translate_html(HTML, boom)
    assert result.stats.failed == 3 and "HTTP 400" in result.failures[0].reason


def test_json_roundtrip_of_failures():
    from plamo_html.report import failures_json

    _, _, result, _ = translate_html(HTML, lambda p: "english only")
    rows = json.loads(failures_json(result.failures))
    assert len(rows) == 3 and rows[0]["last_output"] == "english only"
    assert SETTINGS.form == "plain"
