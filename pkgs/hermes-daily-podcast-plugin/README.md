# hermes-daily-podcast-plugin

Hermes Agent プラグイン。毎日トピック (`hobby-models` など) ごとに Hacker News /
Bluesky / はてなブックマーク / Reddit を巡回し、LLM 2 段構成 (採点は軽量 4B、
要約は 35B、いずれも aperture 経由の hail-mary Ollama) で重要記事を採点・
日本語要約し、VOICEVOX (四国めたん ノーマル) で音声化して、Tailscale 内 nginx
に podcast RSS を配信する。

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
| `HERMES_DAILY_PODCAST_SCORE_MODEL` | no | `qwen3.5:4b-mlx` | 採点 (HIGH/MID/LOW 分類) 用の軽量モデル。候補 30-60 件を一括で裁く |
| `HERMES_DAILY_PODCAST_SUMMARIZE_MODEL` | no | `qwen3.6:35b-mlx` | 1 件ずつ本文を読む要約・翻訳用の重いモデル |
| `HERMES_DAILY_PODCAST_LLM_MODEL` | no | — | 旧 alias。`SCORE_MODEL` / `SUMMARIZE_MODEL` 未設定時の fallback (後方互換) |
| `HERMES_DAILY_PODCAST_LLM_BASE_URL` | no | `http://ai/v1` | Aperture / Ollama OpenAI 互換エンドポイント |
| `OPENAI_API_KEY` | yes (任意値) | — | Aperture は Tailscale identity で代理認証するためダミーで可 |
| `BLUESKY_HANDLE` | no | — | Bluesky source を使う場合。例 `your.bsky.social` |
| `BLUESKY_APP_PASSWORD` | no | — | Bluesky source 用の app password |
| `REDDIT_USER_AGENT` | no | `hermes-daily-podcast/0.1 by /u/anonymous` | Reddit JSON 取得時の UA。Reddit 規約上、識別可能な UA を推奨 |

`hosts/khali/hermes-agent.nix` で `environment` と `environmentFiles` 経由で
セットされる。Bluesky 用 secret は agenix の `daily-podcast-env.age` に格納する
(初期は未配備、Phase 1 では Bluesky は無効)。

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
`https://b.hatena.ne.jp/hotentry/<category>.rss` or `search.rss?q=...`。

| key | 既定値 | 説明 |
| --- | --- | --- |
| `category` | — | `general`/`social`/`economics`/`life`/`knowledge`/`it`/`fun`/`entertainment`/`game` のいずれか。`query` 指定時は無視 |
| `query` | — | キーワード検索 (こちらが優先) |
| `min_users` | 5 | 検索系のときの users 足切り |

### `reddit`
anonymous JSON (`https://www.reddit.com/r/<sub>/top.json`)。`User-Agent` 必須。

| key | 既定値 | 説明 |
| --- | --- | --- |
| `subreddit` | — | サブレディット名 (必須、`r/` プレフィックス無し) |
| `timeframe` | `day` | `hour`/`day`/`week`/`month`/`year`/`all` |
| `limit` | 25 | 取得件数 |
| `min_score` | 10 | 足切り upvote |

将来 `asyncpraw` (OAuth) に乗り換えるとレート制限 60/min まで緩和される (TODO)。

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
- **LLM がタイムアウト**: hail-mary の Ollama が pull 中 / busy。`ollama list | grep qwen3` で tag を確認、必要なら `HERMES_DAILY_PODCAST_SCORE_MODEL` / `HERMES_DAILY_PODCAST_SUMMARIZE_MODEL` を別 tag に差し替え (採点と要約で独立して切替え可)。
- **重複が抑制されない**: `sqlite3 /var/lib/hermes-podcast/state.sqlite 'select count(*) from sources_seen'` で件数確認。タイトル類似度の閾値は `src/dedupe.py:TITLE_SIMILARITY_THRESHOLD`。
- **Bluesky が常に空**: `BLUESKY_HANDLE` / `BLUESKY_APP_PASSWORD` env または `atproto` パッケージが無効。Phase 1 デフォルトでは無効で OK。
- **Reddit が 429**: anonymous レート (10/min) に詰まっている。複数 subreddit を巡回する場合は `INTER_REQUEST_SLEEP` で間隔を空けている。
- **feed が iTunes namespace を含まない**: `feedgen` パッケージが Hermes Python env に未注入。stdlib fallback で簡略 RSS が出る (podcast クライアントは多くがこれで動く)。本格運用するなら `feedgen` を `services.hermes-agent` の Python deps に追加 (将来 TODO)。

## 限界 / 既知の TODO

- `atproto` / `trafilatura` / `feedparser` / `feedgen` / `rapidfuzz` / `url-normalize` を hermes-agent の Python runtime に正式注入する手立てがまだない。本 plugin は全 lib に対して stdlib fallback を実装してあるが、機能差 (要約精度・dedup 精度・RSS 拡張) は出る。Phase 2 で `services.hermes-agent.extraPythonPackages` 相当 API を Nous Research の upstream に提案するか、自前の wrapper Python env を作る案を検討する。
- X (Twitter) 連携は API コスト ($200/月) のため scope outside。Phase 2 で再検討。
- 対談形式 (二人話者) は Phase 2。compose_script に役割切り替えを足し、`role_speakers={"host":2, "guest":3}` を呼び出し側から渡す。
- Apple Podcasts への公式登録は Tailscale Funnel か Cloudflare Tunnel で public URL を取った後 Phase 2。
