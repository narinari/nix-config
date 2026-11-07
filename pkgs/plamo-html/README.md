# plamo-html

英語混じりの静的 HTML を、ローカルの llama-server (PLaMo 3 Translate 8B) で日本語化して別ファイルに書き出す CLI。

```
plamo-html INPUT.html [-o OUTPUT] [--url URL] [--form plain|polite] [--context TEXT]
           [--glossary FILE] [--history-chars N] [--dry-run] [--no-cache] [--report PATH]
```

## オプション

| オプション | 既定 | 説明 |
|---|---|---|
| `INPUT.html` | (必須) | 入力ファイル。読み取りのみ。 |
| `-o`, `--output OUTPUT` | `<入力と同じディレクトリ>/<stem>.ja.html` | 出力先。入力と同一パスならエラー (終了コード 1)。 |
| `--url URL` | `$PLAMO_URL`、無ければ `http://127.0.0.1:8000` | llama-server のベース URL (`/v1/completions` を呼ぶ)。 |
| `--form plain\|polite` | `plain` | 訳文の文体 (PFML3 の `form`)。 |
| `--context TEXT` | `A technical document. Citations, code, file paths and URLs stay as-is.` | プロンプトの context。キャッシュキーに含まれる。 |
| `--glossary FILE` | なし | 用語集 JSON `[{"source": "...", "target": "..."}]`。不正なら起動時にエラー (終了コード 1)。キャッシュキーに含まれる。 |
| `--history-chars N` | `2000` | 直近の (原文, 訳文) 組を合計 N 文字以内で履歴としてプロンプトに入れる。古い順に捨てる。`0` で履歴なし。 |
| `--dry-run` | off | LLM を呼ばず、抽出ブロック数・種別ごとの件数・翻訳対象数・英語文字数 (ラテン文字) を stdout に表示。 |
| `--no-cache` | off | キャッシュの読み書きを両方無効にする。 |
| `--report PATH` | なし | 失敗ブロックを JSON で書き出す。各要素は `index` / `kind` / `source` (プレースホルダ化済み原文) / `reason` / `last_output` (最後のモデル出力、無ければ null)。 |
| `-h`, `--help` | | ヘルプ。 |

引数エラーも終了コード 1 (argparse 既定の 2 は接続不可と衝突するため)。

## 環境変数

| 変数 | 説明 |
|---|---|
| `PLAMO_URL` | `--url` の既定値。 |
| `XDG_CACHE_HOME` | キャッシュ置き場。未設定なら `~/.cache`。 |

## 終了コード

| 値 | 意味 |
|---|---|
| 0 | 完了。failed があっても出力は書く (stderr のサマリと警告で件数を明示)。 |
| 1 | 入力エラー (ファイル不在・パース不能・出力=入力・用語集不正・引数不正)。 |
| 2 | サーバーに接続できない。`systemctl --user start plamo-llama-server` を案内する。出力は書かない (キャッシュは残るので再実行で再開できる)。 |

## 出力・進捗

- 進捗は stderr に `n/total` を 10 件ごと (と最後) に出す。
- 最後に stderr へ `total / translated / cached / skipped_japanese / skipped_other / failed` のサマリ。
- 成功時、stdout に出力ファイルのパスを出す。
- `<html lang>` を `ja` にする。doctype は保持。`id` / `href` / `class` と `<style>` は変更しない。

## 処理の概要

1. **抽出** (lxml.html): ブロック要素内の連続した「テキスト + インライン要素」の run を 1 単位にする (`<li>text<ul>…</ul></li>` の `text` と、`</ul>` 後の続きは別単位)。`<title>`、`meta[name=description]` の content、属性 `alt` / `title` / `aria-label` / `placeholder` も単位になる。順序は title/meta、本文の run (文書順)、属性。`pre code script style svg math textarea`、`translate="no"`、class `notranslate` 配下は触らない。
2. **インライン保護**: `code kbd samp var br img`、文字のない要素、href と本文が同じ URL の `a`、引用 `[Key, 2025]`、`[confidence|disputed|UNVERIFIED …]`、URL は原子 `<x{n}/>`。それ以外のインライン要素は `<b{n}>…</b{n}>` (入れ子可)。訳文は `</?b\d+>|<x\d+/>` だけをトークンとして解釈し、`<` や `&` は生テキスト。原文が既にこの形式や `<|plamo:` を含む単位は翻訳しない。
3. **スキップ**: かな・漢字率 >= 0.2 は `skipped_japanese`。英単語 (3 文字以上) が無い単位、`[引用] … URL` の文献行、予約文字列を含む単位は `skipped_other`。
4. **翻訳**: 文書順に 1 件ずつ `POST {url}/v1/completions` (temperature 0、timeout 180 秒、HTTP 一時エラーは最大 3 回バックオフ再試行)。検証 (トークン多重集合の一致・入れ子・日本語を含む・原文の 4 倍以下) に落ちたら履歴なしで 1 回再試行し、なお不合格なら原文のまま残して failed。
5. **キャッシュ**: `${XDG_CACHE_HOME:-~/.cache}/plamo-translate/html/cache.jsonl` に追記 (1 件ごとに flush)。キーは sha256(context + form + glossary + プレースホルダ化済み原文)。壊れた行は無視する。

用語集はプロンプトで `<|plamo:tag|>glossary<|plamo:index|>{source}<|plamo:item|>{target}` を項目ごとに `index/item` 対で連結して渡す。

## 開発

```
nix shell --impure --expr 'with import <nixpkgs> {}; python3.withPackages (p: [p.lxml p.pytest p.pytest-cov])' -c pytest --cov=plamo_html -q
nix build --impure --expr 'with import <nixpkgs> {}; callPackage ./. {}'
```
