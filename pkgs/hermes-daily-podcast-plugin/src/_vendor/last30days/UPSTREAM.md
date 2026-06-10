# Vendored: mvanhorn/last30days-skill

| field | value |
|-------|-------|
| Upstream | https://github.com/mvanhorn/last30days-skill |
| Commit   | `122158415ae421da83e739f2668032f6bc78d39c` (v3.3.2, 2026-06-06) |
| License  | MIT (see [LICENSE](./LICENSE)) |
| Imported on | 2026-06-11 |

## Files vendored

| Vendor path | Upstream path |
|-------------|---------------|
| `http.py`   | `skills/last30days/scripts/lib/http.py` |
| `log.py`    | `skills/last30days/scripts/lib/log.py` |

`query.py`, `relevance.py`, and `schema.py` are intentionally not vendored —
this plugin uses the host LLM scorer (`../../score.py`) for relevance, and the
host `Candidate` dict (defined in `../../sources/__init__.py`) as the
normalized record shape, so the helpers built around `SourceItem` /
`token_overlap_relevance` from upstream are unused here.

## Intentional differences

`log.py`:

- Reads both `LAST30DAYS_DEBUG` (upstream env) **and** `HERMES_PODCAST_VENDOR_DEBUG`
  (host env). The latter lets the Nix module flip vendor debug logging from a
  single switch without touching upstream files.
- `source_log` is gated on the same DEBUG flag in addition to the existing
  `tty_only` check. Upstream emits `source_log` lines unconditionally to TTYs;
  here we silence them when DEBUG is off, because Hermes runs under systemd and
  noisy stderr ends up in the journal for every poll.

`http.py`:

- `USER_AGENT` was changed from `"last30days-skill/3.0 (Assistant Skill)"` to
  `"hermes-daily-podcast/0.2 (vendored last30days)"` so source providers (Reddit,
  GitHub, etc.) attribute requests to the actual host.
- The convenience helpers `get_text`, `scrapecreators_headers`, and
  `get_reddit_json` are not vendored. They are upstream-specific and unused
  here; the Reddit RSS fetcher in this plugin builds its own browser-shaped
  headers.

No logic changes inside `request()`. If you re-sync from upstream, diff against
the upstream `http.py` and apply only the two header/UA edits above.

## How to refresh

```bash
# pin a newer commit
COMMIT=<sha>
gh repo clone mvanhorn/last30days-skill /tmp/last30days-skill -- --depth 1
cd /tmp/last30days-skill && git checkout "$COMMIT"

# copy the two files
cp skills/last30days/scripts/lib/http.py    .../src/_vendor/last30days/http.py
cp skills/last30days/scripts/lib/log.py     .../src/_vendor/last30days/log.py

# reapply the two diffs above and bump the Commit line in this file.
```
