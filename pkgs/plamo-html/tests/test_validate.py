"""訳文検証のテスト。"""

from plamo_html.model import Protected
from plamo_html.validate import Invalid, Valid, check_translation


def _source(text: str) -> Protected:
    return Protected(text=text, slots={}, has_reserved=False)


def test_accepts_output_identical_to_name_only_source():
    assert isinstance(check_translation(_source('= "Yang et al., 2025".'), '= "Yang et al., 2025".'), Valid)


def test_rejects_changed_output_without_japanese():
    result = check_translation(_source("The risk gate stays outside."), "The risk gate remains outside.")
    assert isinstance(result, Invalid)
    assert result.reason == "output contains no Japanese"


def test_rejects_echoed_english_sentence():
    source = "The risk gate stays outside."
    result = check_translation(_source(source), source)
    assert isinstance(result, Invalid)
    assert result.reason == "output contains no Japanese"
