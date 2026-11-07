import lxml.html

from plamo_html.extract import extract_units
from plamo_html.inline import protect_items, restore
from plamo_html.tokens import tokenize
from plamo_html.validate import Invalid, Valid, check_translation

from helpers import body_html, translate_html


def _units(html):
    return extract_units(lxml.html.document_fromstring(html))


def test_protect_roundtrip_atoms_and_pairs():
    units = _units(
        "<html><body><p>See <a href='/p'>the <em>great</em> paper</a>, "
        "<code>foo()</code> [Li, 2025] http://a.b/c<br>end</p></body></html>"
    )
    text = units[0].protected.text
    assert text == "See <b1>the <b2>great</b2> paper</b1>, <x3/> <x4/> <x5/><x6/>end"


def test_restore_reordered_words_and_nested_pairs():
    root, _, result, _ = translate_html(
        "<html><body><p>Click <a href='/p' class='k'>the <em>big</em> button</a> now</p></body></html>",
        lambda _: "今すぐ <b1><b2>大きな</b2>ボタン</b1> を押す",
    )
    assert result.stats.translated == 1
    assert body_html(root) == (
        "<body><p>今すぐ <a href=\"/p\" class=\"k\"><em>大きな</em>ボタン</a> を押す</p></body>"
    )


def test_literal_atom_restored_as_text_and_special_chars():
    root, _, _, _ = translate_html(
        "<html><body><p>If p &lt; 0.05 &amp; see [Li, 2025] then ok</p></body></html>",
        lambda p: "p < 0.05 & <x1/> を見て良い",
    )
    html = body_html(root)
    assert "p &lt; 0.05 &amp; [Li, 2025] を見て良い" in html


def test_list_item_with_nested_list_translates_each_run():
    root, units, result, _ = translate_html(
        "<html><body><ul><li>Intro text<ul><li>Nested item</li></ul>tail after</li></ul></body></html>",
        lambda p: {"Intro text": "導入", "Nested item": "入れ子", "tail after": "後続"}[
            __import__("helpers").last_src(p)
        ],
    )
    assert len(units) == 3
    assert body_html(root) == (
        "<body><ul><li>導入<ul><li>入れ子</li></ul>後続</li></ul></body>"
    )


def test_validation_rejects_missing_token_and_bad_nesting():
    u = _units("<html><body><p>a <b>bold</b> <code>x</code> word</p></body></html>")[0]
    assert isinstance(check_translation(u.protected, "<b1>太字</b1> 語"), Invalid)
    assert isinstance(check_translation(u.protected, "</b1><b1> <x2/> 語"), Invalid)
    assert isinstance(check_translation(u.protected, "<b1>bold</b1> <x2/> word"), Invalid)
    assert isinstance(check_translation(u.protected, "<b1>太字</b1> <x2/> 語"), Valid)


def test_validation_rejects_overlong_output():
    u = _units("<html><body><p>Hello there</p></body></html>")[0]
    assert isinstance(check_translation(u.protected, "こ" * 100), Invalid)


def test_tokenize_leaves_other_angle_brackets():
    toks = tokenize("a < b <b1>x</b1> & <x2/>")
    assert len(toks) == 6


def test_restore_attribute_untouched_elements_reused():
    root = lxml.html.document_fromstring("<html><body><p>Go <a id='z' href='/q'>there</a></p></body></html>")
    p = protect_items([root.find("body/p").text, root.find("body/p/a")])
    out = restore(p, tokenize("<b1>そこ</b1> へ"))
    assert out[0] is root.find("body/p/a")
