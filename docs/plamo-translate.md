# PLaMo 3 Translate (khali)

khali の RTX 2080 で [PLaMo 3 Translate 8B](https://huggingface.co/pfnet/plamo-3-translate-8b) を動かし、生成済みの HTML を日本語化する。

| 構成要素 | 場所 |
|---|---|
| サーバー `plamo-llama-server` (user service) | `home-manager/narinari/features/llm/plamo-translate.nix` |
| CLI `plamo-html` | `pkgs/plamo-html/` (オプションは同ディレクトリの README) |
| Skill `plamo-translate-html` | `home-manager/narinari/features/llm/claude/skills/plamo-translate-html/` |

## サーバー設定

| 項目 | 値 | 理由 |
|---|---|---|
| 待受 | `127.0.0.1:8000` | khali 内からのみ使う |
| モデル | GGUF Q4_K_M (5.28 GB) | VRAM 使用量 5.4 GB、8 GB に収まる |
| 起動 | `nvidia-offload` 経由 | PRIME offload 構成のため |
| `-c 16384` / `-np 1` | 1 スロット | 文書を直列に翻訳する |
| `--sleep-idle-seconds 300` | 5 分で解放 | Steam などと VRAM を取り合わない。次のリクエストで再ロードされる |
| `cudaCapabilities` | `7.5` のみ | 既定の 10 世代分はビルドが非常に遅い。別の GPU に換えたら更新が必要 |

モデルは `~/.cache/plamo-translate/models/` に置く。無ければ起動時に取得し、SHA-256 を検証する。

## 使い方

```sh
plamo-html report.html --dry-run
plamo-html report.html --context "A research report on ..."
```

`report.ja.html` が出力される。訳はブロック単位で `~/.cache/plamo-translate/html/cache.jsonl` にキャッシュされ、中断しても再開できる。

## インラインタグの扱い

翻訳中のタグは `<x0/>` (中身を訳さない) と `<b1>…</b1>` (中身も訳す) に置き換え、訳文から復元する。`[[0]]` や英字トークンの形式は実測で欠落が出たため使っていない。

## ライセンス

[PLaMo Community License](https://plamo.preferredai.jp/info/plamo-community-license-en)。個人利用は無料。商用利用には登録が必要で、売上が 10 億円を超える場合は別途契約が必要。
