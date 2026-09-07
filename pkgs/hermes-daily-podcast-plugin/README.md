# hermes-daily-podcast-plugin

Hermes Agent プラグイン。毎日トピック (`hobby-models` など) ごとに Hacker News /
Bluesky / はてなブックマーク / Reddit / GitHub Issues / Polymarket / YouTube /
X (xAI Live Search) を巡回し、LLM 2 段構成 (採点は軽量 4B、要約は 35B、いずれも
aperture 経由の hail-mary Ollama) で重要記事を採点・日本語要約し、VOICEVOX
(四国めたん ノーマル) で音声化して、Tailscale 内 nginx に podcast RSS を配信する。

ソース取得層は [`mvanhorn/last30days-skill`](https://github.com/mvanhorn/last30days-skill)
(MIT) の `http.py` / `log.py` を `src/_vendor/last30days/` に取り込み、429 +
Retry-After / DNS gaierror リトライ / API キー秘匿マスキングを共通化している。
詳細は `src/_vendor/last30days/UPSTREAM.md`。

## 公開する Hermes tools

| name | 役割 | 破壊性 |
| --- | --- | --- |
| `generate_daily_episode(topic_slug, target_date?)` | 1 episode 全工程を一括生成 | mp3/RSS を上書き |
| `list_topics()` | topics.toml の現状一覧 | read-only |
| `add_topic(slug, title, description, sources, ...)` | topics.toml にトピックを追加 | 設定を変更 |
| `list_episodes(topic_slug, limit?)` | 過去 episode 一覧 | read-only |
| `regenerate_episode(episode_id, hint?)` | 既存 episode を再生成 | mp3/RSS を上書き |

## 必要な環境変数

| 変数 | 必須 | 既定値 | 説明 |
| --- | --- | --- | --- |
| `DAILY_PODCAST_STATE_DIR` | yes | `/var/lib/hermes-podcast` | mp3/RSS/SQLite を置くルート |
| `DAILY_PODCAST_VOICEVOX_URL` | yes | `http://127.0.0.1:50021` | VOICEVOX engine HTTP API |
| `DAILY_PODCAST_PUBLIC_BASE_URL` | yes | `http://khali/podcasts` | RSS enclosure の URL prefix |
| `DAILY_PODCAST_DEFAULT_SPEAKER_ID` | no | `2` | VOICEVOX speaker id (四国めたん ノーマル) |
| `HERMES_DAILY_PODCAST_SCORE_MODEL` | no | `qwen3.5:4b-mlx` | 採点 (HIGH/MID/LOW 分類) 用モデル。候補 30-60 件を一括で裁く (タイムアウト 600s)。khali では summarize と同じ 27B に統一 — thinking を止められない小型モデルは長い候補リストで空応答になり、別モデル併用はロード切替で OOM を誘発するため |
| `HERMES_DAILY_PODCAST_SUMMARIZE_MODEL` | no | `qwen3.6:35b-mlx` | 1 件ずつ本文を読む要約・翻訳用の重いモデル |
| `HERMES_DAILY_PODCAST_LLM_MODEL` | no | — | 旧 alias。`SCORE_MODEL` / `SUMMARIZE_MODEL` 未設定時の fallback (後方互換) |
| `HERMES_DAILY_PODCAST_LLM_BASE_URL` | no | `http://ai/v1` | Aperture / Ollama OpenAI 互換エンドポイント |
| `OPENAI_API_KEY` | yes (任意値) | — | Aperture は Tailscale identity で代理認証するためダミーで可 |
| `BLUESKY_HANDLE` | no | — | Bluesky source を使う場合。例 `your.bsky.social` |
| `BLUESKY_APP_PASSWORD` | no | — | Bluesky source 用の app password |
| `GITHUB_TOKEN` / `GH_TOKEN` | no | — | `github_issues` source の認証。未設定なら anonymous (60 req/h)、設定すれば 5000 req/h |
| `XAI_API_KEY` | no | — | `x` source の xAI Live Search 用 API キー。未設定なら `x` source は自動 skip |
| `XAI_MODEL` | no | `grok-3-latest` | xAI Live Search で使うモデル名。`x` ソースの `model` 設定で個別上書き可 |
| `DAILY_PODCAST_ALLOW_POPULARITY_FALLBACK` | no | `0` | 採点 LLM 失敗時にブクマ数順フォールバックで生成を続行する opt-in。既定は fail-closed (エピソードを作らず error を返す)。フォールバック時は published_at 7 日超で半減・14 日超で 0 の鮮度減衰つき |
| `HERMES_PODCAST_VENDOR_DEBUG` | no | `0` | vendor http 層 (retry / マスキングログ) の stderr を出力する |
| `REDDIT_USER_AGENT` | no | `hermes-daily-podcast/0.1 by /u/anonymous` | Reddit JSON 取得時の UA。Reddit 規約上、識別可能な UA を推奨 |

`hosts/khali/hermes-agent.nix` で `environment` と `environmentFiles` 経由で
セットされる。Bluesky / GitHub / xAI 用 secret は agenix の
`daily-podcast-env.age` に格納する (詳細は `hosts/khali/hermes-agent.nix` の
`environmentFiles` セクション付近のコメント)。

## トピックの追加方法

`/var/lib/hermes-podcast/topics.toml` が単一情報源。Hermes 経由なら:

```
hermes -p '新しいトピックを追加: slug=ai-tips, title="AI 開発 Tips", description="ローカル LLM 周りの注目記事", sources=[hackernews:"LLM OR \"local LLM\"", hatena:category=it, reddit:LocalLLaMA]'
```

手編集する場合:

```toml
[[topic]]
slug = "ai-tips"
title = "AI 開発 Tips"
description = "ローカル LLM 周りの注目記事を日本語で要約"
voicevox_speaker_id = 2
target_segment_count = 5

[[topic.sources]]
type = "hackernews"
query = "LLM OR \"local LLM\" OR \"ai agent\""

[[topic.sources]]
type = "hatena"
category = "it"

[[topic.sources]]
type = "reddit"
subreddit = "LocalLLaMA"
```

トピックを足したあと、22:00 の自動生成に乗せるには
`hosts/khali/podcast-timer.nix` の `scheduledTopics` に slug を追加して
`sudo nixos-rebuild switch --flake .#khali` する。

注意: `hosts/khali/topics.toml.default` は seed service が**初回のみ**
`/var/lib/hermes-podcast/topics.toml` にコピーする叩き台。以後 Nix は触らない
ため、`topics.toml.default` を更新しても実機には反映されない —
`/var/lib/hermes-podcast/topics.toml` を直接編集すること (毎 run 読み直される
ので service 再起動は不要)。

## ソースタイプ

### `hackernews`
Algolia Search API (`https://hn.algolia.com/api/v1/search`)。

| key | 既定値 | 説明 |
| --- | --- | --- |
| `query` | — | キーワード (必須) |
| `min_points` | 30 | 足切り score |
| `min_comments` | 5 | 足切り comments |
| `limit` | 30 | 1 回の hitsPerPage |

### `bluesky`
`atproto` SDK 経由で `app.bsky.feed.searchPosts`。`BLUESKY_HANDLE` / `BLUESKY_APP_PASSWORD`
env が必要。未設定なら自動 skip。

| key | 既定値 | 説明 |
| --- | --- | --- |
| `query` | — | 検索クエリ (必須) |
| `lang` | — | `ja` などに絞る場合 |
| `limit` | 25 | 取得件数 |

### `hatena`
タグ検索は `https://b.hatena.ne.jp/q/<タグ>?target=tag&mode=rss&sort=recent&...` を
直接叩く (優先順位: tags > query > category)。旧 `search/tag` エンドポイントは
`/q/` へ 301 リダイレクトされる際に `users` / `date_begin` 等の絞り込みが全て
落とされ「過去数年の人気記事」固定になるため使用しない。

| key | 既定値 | 説明 |
| --- | --- | --- |
| `tags` | — | タグのリスト。タグごとに 1 フィード取得してマージ (推奨) |
| `category` | — | `general`/`social`/`economics`/`life`/`knowledge`/`it`/`fun`/`entertainment`/`game` のいずれか。`query` 指定時は無視 |
| `query` | — | キーワード検索 (`search.rss`) |
| `min_users` | 1 | users 足切り。母数優先で低め、選別は LLM 採点に任せる |
| `date_begin` | — | `YYYY-MM-DD`。未指定なら handlers 注入の `since_date` (前回生成日 − 2 日、履歴なしは 30 日前、最大 60 日遡り) が使われる |

### `reddit`
Atom 1.0 RSS (`https://www.reddit.com/r/<sub>/top/.rss`)。ブラウザ風 `User-Agent`
を投げて 403/429 を回避。再試行は vendor http 層 (429 + Retry-After 尊重) に委譲。

| key | 既定値 | 説明 |
| --- | --- | --- |
| `subreddit` | — | サブレディット名 (必須、`r/` プレフィックス無し) |
| `timeframe` | `day` | `hour`/`day`/`week`/`month`/`year`/`all` |
| `limit` | 25 | 取得件数 |

RSS では `score` / `num_comments` を取れないため `min_score` は廃止。最終的な
relevance フィルタは LLM scorer (`src/score.py`) に任せる。

### `github_issues`
GitHub Search API (`https://api.github.com/search/issues`)。OSS の議論・要望・
バグ報告をトピックに沿って拾う。`GITHUB_TOKEN` / `GH_TOKEN` 未設定でも動くが、
anonymous レート (60 req/h) は daily 運用ですぐ枯渇するので token 推奨。

| key | 既定値 | 説明 |
| --- | --- | --- |
| `query` | — | GitHub Search 構文の検索クエリ (必須)。例: `kubernetes label:enhancement` |
| `min_reactions` | 3 | reactions.total_count の足切り |
| `limit` | 25 | per_page (最大 100) |
| `since_days` | 7 | `created:>` で見る日数。1=直近 24h、7=週次 |
| `sort` | `reactions` | `reactions`/`comments`/`created`/`updated` のいずれか |
| `order` | `desc` | `desc`/`asc` |

### `polymarket`
Polymarket Gamma API (`https://gamma-api.polymarket.com/public-search`)。鍵不要、
アクティブな予測市場のみを surface する。スポーツ / 政治 / AI など世論の
ベットを podcast の小ネタとして拾うのに向く。

| key | 既定値 | 説明 |
| --- | --- | --- |
| `query` | — | 検索文字列 (必須) |
| `limit` | 20 | 取得件数の上限 |
| `min_liquidity` | 1000 | これ未満の流動性しかない market は除外 (resolve 寸前 / 死に market 対策) |

### `youtube`
`yt-dlp ytsearch{N}:{query} --dump-json --skip-download` を subprocess で起動して
動画 metadata (title / description / view_count / upload_date / channel) を
抽出する。動画本体や caption はダウンロードしない (downstream LLM が記事/URL を
別途読みに行く想定)。

`yt-dlp` バイナリが PATH に無いと自動 skip する (`hosts/khali/hermes-agent.nix`
の `extraPackages` に同梱)。

| key | 既定値 | 説明 |
| --- | --- | --- |
| `query` | — | YouTube 検索クエリ (必須) |
| `limit` | 10 | `ytsearch{N}` の N |
| `lang` | `ja` | language_hint。要約 prompt のヒントに使う |
| `timeout_seconds` | 180 | subprocess タイムアウト |

### `x`
xAI Live Search 経由で X (Twitter) を検索する。`POST https://api.x.ai/v1/chat/completions`
に `search_parameters.mode=on, sources=[{type:x}]` 付きで投げ、Grok に JSON 配列
を返してもらう方式。`XAI_API_KEY` が未設定なら自動 skip。

LLM の応答パースに依存するため、他ソースよりやや脆い。プロダクション運用前に
出力を必ず眼で確認する。

| key | 既定値 | 説明 |
| --- | --- | --- |
| `query` | — | 検索クエリ (必須) |
| `limit` | 15 | 取得件数の上限 |
| `lang` | `ja` | Grok への言語ヒント (`Prefer posts in language 'ja'`) |
| `model` | env `XAI_MODEL` / `grok-3-latest` | 個別に上書きしたい場合 |

## 出力ファイル

```
/var/lib/hermes-podcast/
├── topics.toml                       # 単一情報源 (mutable)
├── state.sqlite                      # episodes & sources_seen
└── episodes/
    └── <topic-slug>/
        ├── feed.xml                  # podcast RSS (iTunes + Podcast 2.0 ext)
        ├── 2026-05-30.mp3            # daily episode
        ├── 2026-05-30.txt            # 台本 transcript
        └── ...
```

`/podcasts/<topic-slug>/feed.xml` を Pocket Casts / Overcast 等に登録すれば
iPhone (Tailscale 接続) から購読・再生できる。

## トラブルシュート

- **音声が空白**: VOICEVOX engine が落ちている可能性。`systemctl status podman-voicevox-engine` と `curl http://127.0.0.1:50021/version` を確認。
- **LLM がタイムアウト**: hail-mary の Ollama が pull 中 / busy。`ollama list | grep qwen3` で tag を確認、必要なら `HERMES_DAILY_PODCAST_SCORE_MODEL` / `HERMES_DAILY_PODCAST_SUMMARIZE_MODEL` を別 tag に差し替え (採点と要約で独立して切替え可)。タイムアウトを含む全ての transport エラーは `LlmError` に正規化される (`src/llm.py:_post`) ので、topic ごとクラッシュではなくログ + error envelope になるのが正しい挙動。
- **採点 LLM が空応答を返す**: qwen3 系の thinking がトークン枠を食い潰すケース。採点パスは `disable_thinking=True` (`/no_think` + Ollama `think:false`) と `max_tokens=8192` で呼んでおり、`<think>...</think>` がコンテンツに漏れた場合も `chat_json` が除去する。それでも空なら `journalctl -u hermes-agent | grep "valid JSON"` でモデルの生応答を確認。
- **重複が抑制されない**: `sqlite3 /var/lib/hermes-podcast/state.sqlite 'select count(*) from sources_seen'` で件数確認。タイトル類似度の閾値は `src/dedupe.py:TITLE_SIMILARITY_THRESHOLD`。dedup は二段構え: エピソード採用済み URL は**恒久除外** (`state.adopted_urls`)、タイトル fuzzy 一致は直近 14 日窓 (`state.recent_seen`、`last_seen_at` 基準)。`last_seen_at` カラムは初回接続時に自動マイグレーションされる。注意: 恒久除外は `dedupe.normalize_url` の出力で照合するため、URL 正規化ロジックを変更すると過去履歴とミスマッチが起きる (変更時は `sources_seen.normalized_url` の再正規化が必要)。同一日の `regenerate_episode` では、そのエピソード自身が使った記事は除外対象から外れる (同じ素材プールで hint を変えて作り直せる)。
- **Bluesky が常に空**: `BLUESKY_HANDLE` / `BLUESKY_APP_PASSWORD` env または `atproto` パッケージが無効。Phase 1 デフォルトでは無効で OK。
- **Reddit が 429**: vendor http が Retry-After 尊重で 2 回まで自動 retry する。それでも継続的に 429 なら巡回間隔を空ける (topic を分割するか `cron` schedule を調整)。
- **github_issues が常に空 / 403**: 未認証で 60 req/h を超えた可能性。`GITHUB_TOKEN` を `daily-podcast-env.age` に追加する。
- **`x` source が常に空**: `XAI_API_KEY` 未設定 → warn ログを出して自動 skip するのが正しい挙動。設定済みなのに空ならモデル応答が JSON でない可能性。`HERMES_PODCAST_VENDOR_DEBUG=1` で詳細ログを出して確認。
- **youtube が常に空**: `yt-dlp` バイナリが PATH に無い (extraPackages 反映前) か、`yt-dlp` がレート制限を食らっている (`HERMES_PODCAST_VENDOR_DEBUG=1` で yt-dlp の stderr を確認)。
- **feed が iTunes namespace を含まない**: `feedgen` パッケージが Hermes Python env に未注入。stdlib fallback で簡略 RSS が出る (podcast クライアントは多くがこれで動く)。本格運用するなら `feedgen` を `services.hermes-agent` の Python deps に追加 (将来 TODO)。

## 限界 / 既知の TODO

- `atproto` / `trafilatura` / `feedparser` / `feedgen` / `rapidfuzz` / `url-normalize` を hermes-agent の Python runtime に正式注入する手立てがまだない。本 plugin は全 lib に対して stdlib fallback を実装してあるが、機能差 (要約精度・dedup 精度・RSS 拡張) は出る。Phase 2 で `services.hermes-agent.extraPythonPackages` 相当 API を Nous Research の upstream に提案するか、自前の wrapper Python env を作る案を検討する。
- `x` source は xAI Live Search 経由の LLM パース方式に依存しており、応答が JSON でない場合に skip される。本格運用するなら X API v2 (有料) と切替可能なバックエンド層を `src/sources/x.py` に足す。
- 対談形式 (二人話者) は Phase 2。compose_script に役割切り替えを足し、`role_speakers={"host":2, "guest":3}` を呼び出し側から渡す。
- Apple Podcasts への公式登録は Tailscale Funnel か Cloudflare Tunnel で public URL を取った後 Phase 2。

## 開発

Plugin 単体テスト (vendor http + 並列 fetch_all + 既存 config/dedupe テスト):

```bash
cd pkgs/hermes-daily-podcast-plugin
nix shell nixpkgs#python313Packages.pytest -c \
  python -m pytest tests/test_http_vendor.py tests/test_fetch_all_parallel.py \
    tests/test_config.py tests/test_llm.py -q
```

`test_dedupe.py` / `test_score.py` / `test_script.py` は `feedparser` / `rapidfuzz` /
`jinja2` などが必要なため、Hermes Agent runtime と同じ環境 (現状は手動 venv) で
実行する。
