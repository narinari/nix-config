# Claude Code on Podman (Ubuntu/Debian)

公式 devcontainer をベースにした rootless Podman 環境。
`--dangerously-skip-permissions` での自動実行、インタラクティブ利用、マルチエージェント並列実行に対応。

## セットアップ

### 1. Podman インストール (Ubuntu/Debian)

```bash
# Ubuntu 22.04+ / Debian 12+
sudo apt-get update
sudo apt-get install -y podman slirp4netns uidmap

# rootless で動作確認
podman info --format '{{.Host.Security.Rootless}}'
# => true
```

### 2. ビルド & 初回起動

```bash
git clone <this-repo> ~/claude-code-podman
cd ~/claude-code-podman
chmod +x claude-podman

# イメージをビルド
./claude-podman --build --shell
```

### 3. API キー設定

```bash
# 方法1: 環境変数 (.bashrc / .zshrc に追加)
export ANTHROPIC_API_KEY="sk-ant-..."

# 方法2: コンテナ内で設定 (永続化される)
./claude-podman --shell
# コンテナ内で:
claude config set apiKey sk-ant-...
```

## 使い方

### インタラクティブモード

```bash
# カレントディレクトリを /workspace にマウントして起動
cd ~/my-project
~/claude-code-podman/claude-podman
```

### 自動実行モード (--dangerously-skip-permissions)

```bash
# ファイアウォール有効 + 権限スキップで安全に自動実行
cd ~/my-project
~/claude-code-podman/claude-podman --auto

# プロンプトを渡す
~/claude-code-podman/claude-podman --auto -- -p "Fix all lint errors"
```

### マルチエージェント並列実行

```bash
# 3つのエージェントを並列起動 (バックグラウンド)
cd ~/my-project
~/claude-code-podman/claude-podman --auto --agents 3

# 一覧表示
~/claude-code-podman/claude-podman --list

# 特定エージェントにアタッチ
~/claude-code-podman/claude-podman --attach agent-1

# 全停止
~/claude-code-podman/claude-podman --stop
```

### シェルのみ起動

```bash
~/claude-code-podman/claude-podman --shell
```

## オプション一覧

| オプション | 説明 |
|---|---|
| `--auto` | `--dangerously-skip-permissions` で起動 |
| `--shell` | Claude を起動せずシェルのみ |
| `--agents N` | N 個のエージェントを並列起動 |
| `--build` | イメージを強制リビルド |
| `--no-firewall` | ファイアウォール無効 |
| `--name NAME` | コンテナ名を指定 |
| `--list` | 起動中のコンテナ一覧 |
| `--attach NAME` | コンテナにアタッチ |
| `--stop` | 全コンテナ停止 |
| `--` | 以降を claude CLI に渡す |

## セキュリティ

### ファイアウォール (デフォルト有効)

コンテナ起動時に iptables で以下のみ許可:

- `api.anthropic.com` (Claude API)
- `statsig.anthropic.com`, `sentry.io` (テレメトリ)
- `registry.npmjs.org` (npm)
- `github.com`, `api.github.com` (Git)
- `pypi.org`, `files.pythonhosted.org` (pip)
- ローカルネットワーク (MCP サーバー等)
- DNS, SSH

それ以外のアウトバウンドはブロック。

### ファイアウォールのカスタマイズ

`.devcontainer/init-firewall.sh` の `ALLOWED_DOMAINS` 配列にドメインを追加:

```bash
ALLOWED_DOMAINS=(
    # ... 既存のドメイン
    "your-custom-domain.com"    # 追加
)
```

### rootless Podman の分離

- デーモンレス (root プロセスなし)
- ユーザー名前空間による UID マッピング (`--userns keep-id`)
- ワークスペースのみマウント (ホストの他ファイルにアクセス不可)
- `~/.claude` は永続化 (設定・会話履歴)

## ファイル構成

```
claude-code-podman/
├── claude-podman                    # メインランチャー
└── .devcontainer/
    ├── Containerfile                # コンテナイメージ定義
    └── init-firewall.sh             # ネットワークファイアウォール
```

## トラブルシューティング

### iptables エラー

rootless Podman ではデフォルトで `NET_ADMIN` 権限がないため、
ファイアウォールが有効にならない場合があります。

```bash
# 確認
podman run --rm --cap-add=NET_ADMIN alpine iptables -L

# うまくいかない場合は --no-firewall で起動
./claude-podman --no-firewall
```

### subuid/subgid 設定

```bash
# UID マッピングが未設定の場合
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER
podman system migrate
```

### イメージの再ビルド

```bash
./claude-podman --build
```
