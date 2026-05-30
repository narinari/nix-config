"""URL normalization + title fuzzy match dedup.

Phase 1 strategy:
1. Canonicalize URLs (lowercase scheme/host, strip common tracking params,
   drop fragment, trailing slash).
2. Exact match on normalized URL → dedup.
3. Title Jaro similarity >= 0.90 against any seen title → dedup.

Phase 3 will swap step 3 for sentence-transformers embedding cosine.
"""

from __future__ import annotations

import logging
import re
from typing import Iterable
from urllib.parse import parse_qsl, urlencode, urlparse, urlunparse

logger = logging.getLogger(__name__)

# Tracking params we always drop.
_TRACKING_PARAMS = {
    "utm_source",
    "utm_medium",
    "utm_campaign",
    "utm_term",
    "utm_content",
    "utm_id",
    "gclid",
    "fbclid",
    "ref",
    "ref_src",
    "ref_url",
    "mc_cid",
    "mc_eid",
    "_hsenc",
    "_hsmi",
}

TITLE_SIMILARITY_THRESHOLD = 0.90


def normalize_url(url: str) -> str:
    """Return a canonical form suitable for equality comparison."""
    if not url:
        return ""
    try:
        parsed = urlparse(url.strip())
    except ValueError:
        return url.strip()

    scheme = (parsed.scheme or "https").lower()
    netloc = parsed.netloc.lower()
    # strip leading www. for stable identity
    if netloc.startswith("www."):
        netloc = netloc[4:]

    path = parsed.path or "/"
    # collapse multiple slashes
    path = re.sub(r"/+", "/", path)
    # trim trailing slash except for root
    if len(path) > 1 and path.endswith("/"):
        path = path[:-1]

    query_pairs = [
        (k, v)
        for k, v in parse_qsl(parsed.query, keep_blank_values=False)
        if k not in _TRACKING_PARAMS
    ]
    query = urlencode(sorted(query_pairs))

    return urlunparse((scheme, netloc, path, parsed.params, query, ""))


def normalize_title(title: str) -> str:
    """Light normalization for fuzzy matching."""
    s = (title or "").strip().lower()
    # collapse whitespace
    s = re.sub(r"\s+", " ", s)
    # drop common trailing source attributions: "- Some Site", " | Site"
    s = re.sub(r"\s*[-|]\s*[^-|]{1,40}$", "", s)
    return s


def jaro_similarity(a: str, b: str) -> float:
    """Jaro similarity in [0, 1]. Prefer rapidfuzz; fall back to a small impl."""
    if a == b:
        return 1.0
    if not a or not b:
        return 0.0
    try:
        from rapidfuzz.distance import Jaro

        return float(Jaro.similarity(a, b))
    except ImportError:
        return _fallback_jaro(a, b)


def _fallback_jaro(s1: str, s2: str) -> float:
    """Standard Jaro algorithm — used only when rapidfuzz is missing."""
    len1, len2 = len(s1), len(s2)
    match_window = max(len1, len2) // 2 - 1
    if match_window < 0:
        match_window = 0

    s1_matches = [False] * len1
    s2_matches = [False] * len2
    matches = 0
    transpositions = 0

    for i in range(len1):
        start = max(0, i - match_window)
        end = min(i + match_window + 1, len2)
        for j in range(start, end):
            if s2_matches[j]:
                continue
            if s1[i] != s2[j]:
                continue
            s1_matches[i] = True
            s2_matches[j] = True
            matches += 1
            break

    if matches == 0:
        return 0.0

    k = 0
    for i in range(len1):
        if not s1_matches[i]:
            continue
        while not s2_matches[k]:
            k += 1
        if s1[i] != s2[k]:
            transpositions += 1
        k += 1
    transpositions //= 2

    return (
        matches / len1
        + matches / len2
        + (matches - transpositions) / matches
    ) / 3.0


def is_duplicate(
    candidate_url: str,
    candidate_title: str,
    seen: Iterable[tuple[str, str]],
) -> bool:
    """True if (url, title) collides with any item in `seen`."""
    norm_url = normalize_url(candidate_url)
    norm_title = normalize_title(candidate_title)
    for seen_url, seen_title in seen:
        if seen_url and seen_url == norm_url:
            return True
        if (
            norm_title
            and seen_title
            and jaro_similarity(norm_title, normalize_title(seen_title))
            >= TITLE_SIMILARITY_THRESHOLD
        ):
            return True
    return False
