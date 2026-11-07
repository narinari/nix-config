import pytest

from plamo_html.inline import protect_text
from plamo_html.skip import SkipKind, classify


@pytest.mark.parametrize(
    "text,expected",
    [
        ("これは日本語の文章です。", SkipKind.JAPANESE),
        ("gap_g01_19f994a71c4c", SkipKind.OTHER),
        ("TDnet", SkipKind.OTHER),
        ("12.5%", SkipKind.OTHER),
        (
            "[GuruAgents, 2025] GuruAgents: Emulating Investors — https://arxiv.org/pdf/2510.01664",
            SkipKind.OTHER,
        ),
        ("Contents", None),
        ("This is a normal English sentence.", None),
        ("Hello <x9/> <b1>", SkipKind.OTHER),
        ("uses <|plamo:tag|> inside text", SkipKind.OTHER),
    ],
)
def test_classify(text, expected):
    skip = classify(protect_text(text))
    assert (skip.kind if skip else None) == expected


def test_mixed_text_with_enough_japanese_is_skipped():
    assert classify(protect_text("決算 Q3 results 発表")).kind is SkipKind.JAPANESE
