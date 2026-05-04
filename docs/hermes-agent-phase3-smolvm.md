# Hermes Agent Phase 3 — SmolVM サンドボックス連携

別セッションで作業を再開するためのドキュメント。Phase 1 (Hermes Agent 本体導入)
と Phase 2 (Aperture 経由 LLM 接続のデバッグ + Discord 連携) は完了済み。
本ドキュメントは **Phase 3 = Hermes Agent が生成したコードを SmolVM 内で
安全実行する仕組み** の実装計画。

## ゴール

Hermes Agent が `terminal` ツールでコマンド実行する際に、ホスト khali の
シェルを直接叩くのではなく、**CelestoAI/SmolVM** の microVM 内で実行させる。
コード生成エージェント (Hermes 自身、または delegate された Claude Code/Codex)
の暴走による khali への被害を防ぐ。

### スコープ
- okane-family などの実装作業を Hermes 経由で進めるとき、生成されたコードを
  サンドボックスで安全に実行する経路を提供する
- Hermes terminal backend を local → smolvm wrapper に置換
- agent (Hermes) の自己改変・apt install 等を VM 内に閉じ込める

### 非スコープ
- Hermes 本体を VM に閉じ込める (smol-machines/smolvm 案 — 別検討)
- 既存 Aperture 接続の変更 (Phase 1 で完成済み)

## 現状の Phase 1/2 構成

ファイル: `/home/narinari/nix-config/hosts/khali/hermes-agent.nix`

```nix
services.hermes-agent.settings.terminal = {
  backend = "local";  # ← ここを smolvm wrapper に置換するのが Phase 3
  timeout = 180;
};
```

### Hermes terminal backend の選択肢 (`cli-config.yaml.example` より)

`local`, `ssh`, `docker`, `singularity`, `modal`, `daytona` の 6 種が公式実装。
**`smolvm` は未実装** のため、以下のいずれかが必要:

1. SmolVM を OCI 互換に見せて `docker` backend で利用 (smolvm が docker socket を
   提供するか不明 — 要調査)
2. SmolVM の Python SDK を使うカスタム backend を Hermes plugin として追加
3. `local` backend のまま、`extraPackages` 経由で `smolvm` CLI を入れて、
   Hermes がコマンドの先頭に `smolvm run -- ` を付けるよう system_prompt で誘導
   (緩い保証だが最小工数)

## SmolVM (CelestoAI) 概要

- リポジトリ: <https://github.com/CelestoAI/SmolVM>
- 形態: Python パッケージ (`pip install smolvm`) + CLI (`smolvm`)
- 隔離: Linux 上では Firecracker、macOS では QEMU/Hypervisor.framework
- インストール: `curl -sSL https://celesto.ai/install.sh | bash` または `pip install smolvm`
- Python SDK 例:
  ```python
  from smolvm import SmolVM
  vm = SmolVM()
  result = vm.run("echo 'Hello from the sandbox!'")
  vm.stop()
  ```
- 起動コスト: Sub-second boot (~500ms)
- OCI image 起動可能: Docker Hub / ghcr.io から pull

## 実装プラン

### ステップ 1: smolvm を Nix パッケージ化

#### 1a. Python wheel として packaging

`pkgs/smolvm/default.nix` を新規作成:

```nix
{ python312Packages, fetchPypi }:

python312Packages.buildPythonPackage rec {
  pname = "smolvm";
  version = "X.Y.Z";  # PyPI 最新版を確認
  src = fetchPypi {
    inherit pname version;
    hash = "sha256-...";
  };
  # Firecracker binary は runtime fetch される設計の可能性 → 要調査
  propagatedBuildInputs = with python312Packages; [ /* ... */ ];
}
```

調査ポイント:
- `pip show smolvm` で依存パッケージ確認 (curl ... | bash でインストールして確認可)
- Firecracker binary を smolvm がどう解決するか (bundled? path lookup?)
- `smolvm setup` / `smolvm doctor` が要求する system 設定

#### 1b. Firecracker の準備

NixOS には `pkgs.firecracker` がある:

```nix
# hosts/khali/default.nix またはモジュール
environment.systemPackages = [ pkgs.firecracker ];

# /dev/kvm への user アクセス
users.users.hermes.extraGroups = [ "kvm" ];
boot.kernelModules = [ "kvm-intel" ];  # Intel CPU 用
```

### ステップ 2: Hermes の terminal backend を SmolVM 経由に切り替え

#### Option A (推奨): カスタム plugin 開発

Hermes は `services.hermes-agent.extraPlugins` で plugin 追加可能
(`hermes-agent.nix` の module ソース 489 行目付近参照)。

`pkgs/hermes-smolvm-plugin/` を作成:

```python
# hermes_smolvm_plugin/__init__.py
from hermes_agent.terminal import register_backend
from smolvm import SmolVM

class SmolVMBackend:
    name = "smolvm"
    def __init__(self, config):
        self.vm = SmolVM(image=config.get("image", "python:3.12-slim"))
    def run(self, cmd, timeout=180):
        return self.vm.run(cmd, timeout=timeout)
    def shutdown(self):
        self.vm.stop()

register_backend("smolvm", SmolVMBackend)
```

それを extraPlugins に追加:

```nix
services.hermes-agent.extraPlugins = [
  (pkgs.python312Packages.callPackage ../pkgs/hermes-smolvm-plugin {})
];

services.hermes-agent.settings.terminal = {
  backend = "smolvm";
  smolvm_image = "python:3.12-slim";
  timeout = 180;
};
```

#### Option B (低工数): wrapper script

`local` backend のまま、`extraPackages` で smolvm CLI を入れて、
コマンドプレフィックスを system_prompt で強制:

```nix
services.hermes-agent.extraPackages = [ pkgs.smolvm ];
services.hermes-agent.settings.agent.system_prompt_prefix = ''
  常に日本語で応答すること。コードや shell コマンドを実行する場合は必ず
  `smolvm run -- <cmd>` の形式で wrap すること。直接ホスト上で実行しない。
  ${existing_japanese_prompt}
'';
```

⚠ 弱保証 (LLM が prompt を無視する可能性あり)。本番運用は Option A 推奨。

### ステップ 3: ネットワーク・ファイル共有方針

- okane-family のソースをサンドボックスに mount するか?
- → Yes (`smolvm create --mount /home/narinari/dev/...`)。Hermes の workspace
  を VM 内 `/workspace` に bind mount する設計が自然
- ネットワークは `internet_settings` で制限可能 (CelestoAI README 参照)
  - 開発時は `allow_all`、本番運用時は allow-list

## 検証手順

### Phase 3a: Nix パッケージ化単体テスト
```bash
nix build .#smolvm
./result/bin/smolvm doctor   # 依存チェック
./result/bin/smolvm create --name test
./result/bin/smolvm ssh test  # VM に入れる確認
```

### Phase 3b: Hermes 連携テスト
```bash
sudo nixos-rebuild switch --flake ~/nix-config#khali
hermes -z "Run 'echo hello && hostname' and report the hostname" --yolo
# 期待: hostname が khali ではなく VM のもの
```

### Phase 3c: 安全性テスト
```bash
hermes -z "rm -rf /tmp/test_only_in_vm" --yolo
ls /tmp/test_only_in_vm  # ホスト側にファイルが影響しないこと
```

## 参考リソース

### コードベース内
- `hosts/khali/hermes-agent.nix` — 現状の Phase 1/2 構成
- `home-manager/narinari/features/llm/codex.nix` — Aperture 経由構成のリファレンス
- `pkgs/` — Nix カスタムパッケージの命名規約 (例: `pkgs/macskk/`, `pkgs/fosi/`)
- `modules/services/` — service モジュールの構造 (例: mirakurun)

### 外部
- SmolVM (CelestoAI): <https://github.com/CelestoAI/SmolVM>
- Hermes Agent docs: <https://hermes-agent.nousresearch.com/docs/>
- Hermes terminal backend example: NousResearch/hermes-agent リポジトリの
  `cli-config.yaml.example` の Terminal Tool Configuration セクション
- Hermes NixOS module options: `nix/nixosModules.nix` of NousResearch/hermes-agent

### メモリ
- `~/.claude/projects/-home-narinari-nix-config/memory/feedback_hermes_custom_provider.md`
  — Hermes でカスタム OpenAI 互換エンドポイントを使う際の罠 (Phase 1/2 で発見)

## 既知の懸念

1. **Firecracker は KVM 必須** — khali (Intel CPU + KVM 対応) では動くが、
   仮想化を許可していない CI / クラウド VM では動かない。`smolvm doctor` で
   detect させる
2. **smolvm は curl install 前提** — Nix パッケージ化時に PyPI 版に依存が
   揃っているか要検証。`/usr/local/bin/firecracker` 等 FHS 前提だと NixOS で
   patchelf が必要
3. **Hermes plugin API の安定性** — 公式 plugin example が少ない (Phase 1 で
   `extraPlugins` option は確認済みだがランタイム規約は未調査)
4. **VM コールドスタート** — Sub-second とはいえ、毎コマンド VM 起動だと
   遅延が累積する。VM をセッション中再利用する設計が望ましい

## 着手順序 (1 セッション目安)

1. 30 min: SmolVM を pip インストールして手動検証 (smolvm doctor / create / run)
2. 30 min: Hermes plugin API 調査 (`extraPlugins` の規約、register_backend 相当が
   あるか source 確認)
3. 60 min: Option B (wrapper) で動作確認 (system_prompt 経由) — まず動かす
4. 残り: Option A (plugin) の実装 / Nix packaging
