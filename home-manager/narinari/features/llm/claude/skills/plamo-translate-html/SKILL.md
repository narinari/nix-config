---
name: plamo-translate-html
description: 英語または英語混じりの静的 HTML を、khali のローカル PLaMo 3 Translate で日本語化して `<stem>.ja.html` に書き出す。Deeper Research の HTML レポートなど、生成済み HTML の翻訳を頼まれたときに使う。
origin: nix-config (home-manager features/llm)
version: "0.1.0"
allowed-tools: Read Grep Bash(plamo-html:*) Bash(systemctl --user start plamo-llama-server) Bash(systemctl --user status plamo-llama-server:*) Bash(journalctl --user -u plamo-llama-server:*)
argument-hint: "<input.html>"
---

# plamo-translate-html

`plamo-html` で HTML を翻訳する。元ファイルは変更しない。khali 以外では動かない。

## 使わない場合

- `<script>` で本文を描画するページ。HTML に本文が無いので翻訳できない
- Markdown やプレーンテキスト

## 手順

1. 件数を確認する。

   ```sh
   plamo-html INPUT.html --dry-run
   ```

2. サーバーを起動する。起動済みなら何も起きない。

   ```sh
   systemctl --user start plamo-llama-server
   ```

3. 文書の分野を `--context` に書いて翻訳する。大きなファイルは 10 分以上かかるので、バックグラウンドで実行する。

   ```sh
   plamo-html INPUT.html --context "A research report on ..." --report INPUT.report.json
   ```

   途中で止まっても、同じコマンドでキャッシュから再開できる。

4. stderr のサマリと `--report` を確認し、出力先、件数、`failed` の傾向を報告する。`failed` のブロックは原文の英語のまま残っている。

訳語を揃えたいときは `--glossary` に `[{"source": "...", "target": "..."}]` 形式の JSON を渡す。

## 翻訳されないもの

- `pre`、`code` の中身
- 引用 (`[Author, Year]`)、`[confidence: ...]`、URL
- 既に日本語のブロック
- 文献リストの行 (`[Key, Year] Title — URL`)
