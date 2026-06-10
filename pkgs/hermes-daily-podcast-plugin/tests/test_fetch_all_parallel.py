"""Verify ``sources.fetch_all`` runs registered fetchers concurrently and
preserves the input order in the flattened result.
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from src import config as cfg  # noqa: E402
from src import sources  # noqa: E402


SLEEP_SECONDS = 0.4


@pytest.fixture
def fake_sources(monkeypatch):
    """Register 4 slow fakes for the duration of the test."""
    saved = sources._REGISTRY.copy()

    def make_fake(name: str):
        def _fetch(_source):
            time.sleep(SLEEP_SECONDS)
            return [{"url": f"https://example.invalid/{name}", "title": name}]

        return _fetch

    names = ["fake_a", "fake_b", "fake_c", "fake_d"]
    for n in names:
        sources.register(n)(make_fake(n))

    yield names

    sources._REGISTRY.clear()
    sources._REGISTRY.update(saved)


def test_fetch_all_runs_sources_in_parallel(fake_sources):
    configs = [cfg.SourceConfig(type=t) for t in fake_sources]

    start = time.monotonic()
    results = sources.fetch_all(configs)
    elapsed = time.monotonic() - start

    # Serial execution would be 4 * SLEEP_SECONDS = 1.6s. With max_workers=4 we
    # expect roughly one SLEEP_SECONDS plus thread-pool overhead. Allow a
    # generous ceiling — we only need to prove "well under the serial time".
    assert elapsed < (SLEEP_SECONDS * 4) - 0.4, (
        f"fetch_all looks serial: took {elapsed:.2f}s"
    )

    assert [r["url"].rsplit("/", 1)[-1] for r in results] == fake_sources


def test_fetch_all_preserves_source_order_under_uneven_completion(monkeypatch):
    """The slowest source must still land last in the flattened list."""
    saved = sources._REGISTRY.copy()

    delays = {"slow": 0.30, "fast_a": 0.05, "fast_b": 0.05}
    for name, delay in delays.items():

        def make(name=name, delay=delay):
            def _fetch(_s):
                time.sleep(delay)
                return [{"url": f"https://example.invalid/{name}", "title": name}]

            return _fetch

        sources.register(name)(make())

    try:
        configs = [
            cfg.SourceConfig(type="slow"),
            cfg.SourceConfig(type="fast_a"),
            cfg.SourceConfig(type="fast_b"),
        ]
        result = sources.fetch_all(configs)
        assert [r["source"] for r in result] == ["slow", "fast_a", "fast_b"]
    finally:
        sources._REGISTRY.clear()
        sources._REGISTRY.update(saved)


def test_fetch_all_isolates_failing_source(monkeypatch):
    saved = sources._REGISTRY.copy()

    def boom(_source):
        raise RuntimeError("kaboom")

    def ok(_source):
        return [{"url": "https://example.invalid/ok", "title": "ok"}]

    sources.register("boom_src")(boom)
    sources.register("ok_src")(ok)

    try:
        configs = [
            cfg.SourceConfig(type="boom_src"),
            cfg.SourceConfig(type="ok_src"),
        ]
        result = sources.fetch_all(configs)
        # Failing source contributes nothing; healthy one still lands.
        assert [r["source"] for r in result] == ["ok_src"]
    finally:
        sources._REGISTRY.clear()
        sources._REGISTRY.update(saved)
