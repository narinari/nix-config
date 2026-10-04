# hail-mary Ollama 運用メモ

hail-mary (MacBook Pro M1 Max 10C / 統合メモリ 64GB / macOS 15.x) 上の Ollama を、
khali の Hermes Agent / codex CLI / Claude Code skill から Tailscale Aperture (`http://ai/v1`)
経由で共有利用している。本書は env・モデル tag 選定・反映手順・実測値をまとめる。

関連: [codex-implement-claude-bridge.md](codex-implement-claude-bridge.md),
`home-manager/narinari/darwin/ollama.nix`, `hosts/khali/hermes-agent.nix`,
`home-manager/narinari/features/llm/codex.nix`

## 構成

```
khali (Hermes / codex / Claude Code)
    │  OpenAI 互換 API, Tailscale identity 認証 (API key はダミー)
    ▼
Tailscale Aperture  http://ai/v1
    │
    ▼
hail-mary  Ollama.app (Homebrew cask `ollama-app`) :11434
           └─ MLX runner (safetensors 形式 tag: -mlx / -nvfp4 / -mxfp8 / -mlx-bf16)
           └─ llama.cpp Metal runner (GGUF tag: -q4_K_M / -q8_0 等)
```

- Ollama は **Homebrew cask `ollama-app`** (`hosts/common/darwin/homebrew.nix`)。nixpkgs の
  `services.ollama` は MLX runner が使えないため使っていない。
- GUI app (Electron) が `ollama serve` を子プロセスとして起動する。`launchctl list` では
  `com.ollama.ollama` (SMAppService ログイン項目) と `application.com.electron.ollama.*` に見える。
- runner の選択は **tag のファイル形式で自動決定** される。`OLLAMA_MLX` のような切替 env は無い。

## 環境変数 (`home-manager/narinari/darwin/ollama.nix`)

GUI app は shell の env を引き継がないため、`home.sessionVariables` (CLI / SSH 用) と
`launchd.agents.ollama-env` (`launchctl setenv`、GUI 用) の **両方に同じ値** を流している。

| 変数 | 値 | 目的 | MLX runner で効くか |
|---|---|---|---|
| `OLLAMA_HOST` | `0.0.0.0:11434` | Tailscale / aperture から到達できるよう全 IF で listen | ○ (server 設定) |
| `OLLAMA_KEEP_ALIVE` | `24h` | Hermes の約 1 時間周期ジョブが毎回 cold-load (~10s + cold prefill) を払わないよう常駐。aperture 経由の cold-load 起因 502 も排除 | ○ |
| `OLLAMA_MAX_LOADED_MODELS` | `2` | 既定 `qwen3.8:27b-mlx` (18GB) + fallback `gemma4:26b-a4b-it-q8_0` (28GB) まで。3 本同居は 64GB (GPU 可視 48GiB) で Metal OOM 実績あり | ○ |

**意図的に設定していないもの**

| 変数 | 理由 |
|---|---|
| `OLLAMA_NUM_PARALLEL` | MLX runner は無視して常に `Parallel:1` (server.log で確認)。以前の `2` は削除 |
| `OLLAMA_CONTEXT_LENGTH` | 既定は VRAM 判定で `262144` (48GiB ティア)。MLX は KV を遅延確保するため 256K 宣言でも実メモリは会話長に比例 (27B mxfp8 時点の実測で peak 35.8GiB)。小さくすると codex の `model_context_window = 262144` との不整合で silent truncation を招くので触らない。長会話でメモリ逼迫したら `65536`〜`131072` を候補に |
| `OLLAMA_FLASH_ATTENTION` / `OLLAMA_KV_CACHE_TYPE` | llama.cpp runner 向け。MLX runner には無関係 |

### `launchctl setenv` は揮発的

`launchctl setenv` の値は **再起動で消える**。`ollama-env` LaunchAgent (`RunAtLoad=true`) が
ログイン時に再設定する唯一の永続化手段なので、Nix 側の変更は **darwin-rebuild が実機で
走っていること** まで確認する。2026-10 の調査では commit 後 4 ヶ月 rebuild されておらず、
再起動後に `OLLAMA_KEEP_ALIVE=5m` (既定) に戻っていた。

反映確認 (**ssh 越しの `launchctl getenv` は使わない**、下記「ドメインの罠」参照):

```sh
ls ~/Library/LaunchAgents/ | grep ollama-env                     # com.narinari.ollama-env.plist
launchctl print gui/$(id -u)/com.narinari.ollama-env | grep -E 'runs|last exit'   # 実行済み・exit 0
launchctl print gui/$(id -u) | grep -E 'OLLAMA_'                 # GUI ドメインの環境に 3 変数
ps eww -o command= -p "$(pgrep -f 'ollama serve')" | tr ' ' '\n' | grep '^OLLAMA_'   # 実プロセスの env
grep -E 'OLLAMA_KEEP_ALIVE' ~/.ollama/logs/server.log | tail -1  # 起動時の実効値 (24h0m0s)
```

### launchd ドメインの罠 (2026-10-04 実測)

`launchctl setenv` / `getenv` は **呼び出し元プロセスが属するドメイン** に作用する。
- `ollama-env` agent (gui/UID) と Ollama.app (gui/UID) は同じドメイン → 正しく届く
- **ssh ログインセッションは user/UID (Background) ドメイン** → ssh から `launchctl getenv
  OLLAMA_KEEP_ALIVE` を叩くと **空に見える** (偽陰性)。逆に ssh から `launchctl setenv` しても
  GUI アプリには届かない
- 確認は `launchctl print gui/$(id -u)` か、`ollama serve` プロセスの `ps eww` で行う

`launchctl setenv` は **新規 spawn プロセスにしか効かない** ので、rebuild 後は Ollama.app を再起動する:

```sh
pkill -x Ollama && sleep 3 && open -a Ollama   # osascript quit は拒否されることがある
```

## モデル tag の選定

### 既定: `qwen3.8:27b-mlx` (MLX 4bit = nvfp4, 18GB)

M1 Max の decode はメモリ帯域 (400GB/s) 律速。27.8B dense の重みを 1 token ごとに読むため、
**8bit (mxfp8, 32GB) では約 14 tok/s が理論上限**、4bit で約 2 倍の余地がある。
Q4 系の品質低下は Terminal-Bench 等で BF16 とほぼ同等という評価が複数あり、
実測 1.44x (14.1 → 20.3 tok/s)、cold load 9.6s → 3.0s とのトレードオフで 4bit を採用。
`ollama show` の quantization は `nvfp4` と出る (`27b-nvfp4` tag と同一 digest)。

### 実測 (2026-10-04, `/api/generate`, 短プロンプト 23 tok, `num_predict: 200`, warm)

| tag | 構造 | サイズ | gen tok/s | prefill tok/s | cold load |
|---|---|---|---|---|---|
| `qwen3.8:27b-mxfp8` | 27.8B dense, 8bit | 32GB | 14.1 | 147 (短) / 100 (1660 tok) | 9.6 s |
| `qwen3.8:27b-mlx` | 27.8B dense, 4bit (nvfp4) | 18GB | **20.3** | 161 (短) / 107 (1820 tok) | 3.0 s |
| `qwen3.6:35b-mlx` | 35B MoE (A3B) | 22GB | 58.2 | 293 | 7.5 s |
| `qwen3.5:4b-mlx` | 4B dense | 4.2GB | 70.9 | 351 | 1.3 s |

- Qwen3.8-27B は hybrid Gated DeltaNet (線形注意 48 層 + full attention 16 層) で、同サイズの
  Qwen3.6-27B より decode が遅いという報告が複数ある (Metal カーネル成熟度)。
- 速度最優先の用途には `qwen3.6:35b-mlx` (MoE, 58 tok/s) が 4 倍速い。品質は 27B dense 優位。
- thinking は既定 `medium`。1 リクエスト 1 分超の大半は thinking 700〜1000 tok の生成。
  品質に寄与するため現状維持 (必要なら client 側で `think` を下げる)。

### Qwen3.8-Flash-Next (125B-A6B) は見送り (2026-10 判断)

- Ollama 公式 tag は最小 **105GB** (`125b-mlx` = nvfp4)。51B パラメータの N-gram 埋め込み
  テーブルを含めて全量 wired するため 64GB では不可。省メモリ化 PR
  [ollama/ollama#18078](https://github.com/ollama/ollama/pull/18078) はマージ後も 70.8GiB で 128GB 向け。
- [lilting.ch の M1 Max 検証](https://lilting.ch/articles/qwen38-flash-next-llamacpp-m1max-test)
  は llama.cpp (unsloth PR) + N-gram テーブルを SSD に mmap する特殊 GGUF で **tg 17.6 tok/s**。
  27B 4bit と同等の速度で、experts は実質 2bpw (IQ1_M/IQ2_S)、空きメモリ 0.1GB、
  `iogpu.wired_limit_mb` 変更必須、Ollama と別運用になる。
- 再検討条件: Ollama MLX runner が N-gram テーブルの分離 (mmap / CPU オフロード) に対応し、
  64GB で常駐 45GB 以下になったら。

## 反映 runbook

1. 作業マシン (khali) で編集 → commit → `git push origin main`
2. hail-mary で pull + rebuild:
   ```sh
   ssh hail-mary.local 'cd ~/nix-config && git pull --ff-only && darwin-rebuild switch --flake ~/nix-config#hail-mary'
   ```
3. 上記「反映確認」で `launchctl getenv` を確認 → Ollama.app を再起動
4. モデル tag を変えた場合は hail-mary で `ollama pull <tag>` し、`curl -s http://ai/v1/models` に出ることを確認。
   切替が安定したら旧 tag を `ollama rm <old-tag>` で解放する (27b-mxfp8 は 31GB)
5. khali 側 (`hosts/khali/hermes-agent.nix`) は `sudo nixos-rebuild switch --flake ~/nix-config#khali`

## トラブルシュート

| 症状 | 原因 | 対処 |
|---|---|---|
| 1 時間ごとの Hermes ジョブで毎回 10 秒待つ / aperture 502 | `OLLAMA_KEEP_ALIVE` が既定 5m に戻っている | `launchctl print gui/$(id -u) \| grep OLLAMA` が空なら rebuild → `launchctl kickstart -k gui/$(id -u)/com.narinari.ollama-env` → Ollama.app 再起動 |
| `osascript -e 'quit app "Ollama"'` が「ユーザによってキャンセル」で失敗 | Ollama.app が quit を拒否 | `pkill -x Ollama && sleep 3 && open -a Ollama` で再起動 |
| `launchctl list` に `homebrew.mxcl.ollama` が exit 78 で残る | 旧 brew formula の LaunchAgent plist (formula 未インストール) | `launchctl bootout gui/$(id -u)/homebrew.mxcl.ollama && rm ~/Library/LaunchAgents/homebrew.mxcl.ollama.plist` |
| `[METAL] Insufficient Memory` / ロード切替で OOM | 複数モデル同居 | `ollama ps` で確認、`OLLAMA_MAX_LOADED_MODELS` を下げる、ワークフロー内でモデルを統一 |
| 生成が 14 tok/s 前後で頭打ち | 8bit dense の帯域律速 (正常動作) | 4bit tag か MoE tag へ |
| `ollama ps` の PROCESSOR が `100% GPU` 以外 | GGUF tag で VRAM 不足 → CPU オフロード | MLX tag を使う / 小さい量子化へ |
| GPU 利用率 50〜70% で遅い (Ollama 0.40.0) | MLX runner の regression ([#18754](https://github.com/ollama/ollama/issues/18754)) | 0.35.x に留める / 修正版へ更新 |
