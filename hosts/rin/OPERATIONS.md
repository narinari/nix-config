# Rin LXC 運用ガイド

Proxmox上のリモート開発環境LXCコンテナ。

## 概要

| 項目 | 値 |
|------|-----|
| ホスト名 | rin.local |
| プラットフォーム | x86_64-linux (Proxmox LXC) |
| 用途 | リモート開発環境 |
| Emacs | emacs-nox (ターミナル版) |
| コンテナランタイム | Podman (Docker互換) |

## 初回セットアップ

### 1. テンプレートビルド

```bash
cd ~/dev/src/github.com/narinari/nix-config
nix build .#rin-lxc
```

### 2. Proxmoxへ転送

```bash
scp result/tarball/nixos-image-lxc-proxmox-*.tar.xz \
  root@art.local:/var/lib/vz/template/cache/nixos-lxc-rin.tar.xz
```

### 3. 永続ストレージ作成（Proxmoxホスト上）

```bash
# ディレクトリ作成
mkdir -p /mnt/data/rin-dev

# unprivileged LXC用のUID mapping (100000 = LXC内のUID 0)
chown 101000:101000 /mnt/data/rin-dev  # narinari (UID 1000)
```

### 4. LXC作成

```bash
# VMID 200 は空き番号に変更
pct create 200 /var/lib/vz/template/cache/nixos-lxc-rin.tar.xz \
  --hostname rin \
  --memory 8192 \
  --cores 4 \
  --rootfs local-lvm:32 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --features nesting=1 \
  --unprivileged 1 \
  --ostype unmanaged

# 永続ストレージをマウント
pct set 200 -mp0 /mnt/data/rin-dev,mp=/home/narinari/dev

# ファイルディスクリプタ上限を設定（開発ツール用）
cat >> /etc/pve/lxc/200.conf << 'EOF'

# ファイルディスクリプタ上限（LSP、ファイルウォッチャー等に必要）
lxc.prlimit.nofile: 1048576
EOF
```

### 5. 起動と初期設定

```bash
pct start 200
pct enter 200

# LXC内で実行
chown -R narinari:users /home/narinari/dev
```

## 日常運用

### SSH接続

```bash
ssh rin.local
# または
ssh narinari@rin.local
```

### システム更新

Mac側から deploy-rs で更新:

```bash
cd ~/dev/src/github.com/narinari/nix-config
deploy .#rin
```

または LXC内で直接:

```bash
sudo nixos-rebuild switch --flake github:narinari/nix-config#rin
```

### LXC操作（Proxmoxホスト上）

```bash
# 起動/停止/再起動
pct start 200
pct stop 200
pct reboot 200

# コンソール接続
pct enter 200

# 状態確認
pct status 200
```

## バックアップ

### Proxmox標準バックアップ

```bash
# 手動バックアップ
vzdump 200 --storage local --compress zstd --mode snapshot

# cronで毎日3時にバックアップ（/etc/cron.d/rin-backup）
0 3 * * * root vzdump 200 --storage local --compress zstd --mode snapshot --mailto root
```

### 開発ディレクトリのみバックアップ

```bash
# restic使用例
restic -r sftp:nas:/backup/rin-dev backup /mnt/data/rin-dev
```

### 復元

```bash
# Proxmox標準復元
pct restore 200 /var/lib/vz/dump/vzdump-lxc-200-*.tar.zst --storage local-lvm

# または新規作成して永続ストレージを再マウント
```

## トラブルシューティング

### Podmanが動かない

nesting機能が有効か確認:

```bash
pct config 200 | grep features
# features: nesting=1 が必要
```

### ネットワークに接続できない

```bash
# LXC内で
ip addr
ping -c 1 8.8.8.8

# Proxmoxホストで
pct config 200 | grep net
```

### mDNS (rin.local) で接続できない

Avahiが動作しているか確認:

```bash
# LXC内で
systemctl status avahi-daemon
```

### ディスク容量不足

```bash
# Proxmoxホストで rootfs 拡張
pct resize 200 rootfs +10G
```

### SSH接続でPermission denied

PAMエラーの可能性。ホスト側でlxc.prlimit.nofileが設定されているか確認:

```bash
# Proxmoxホストで
grep prlimit /etc/pve/lxc/200.conf
# lxc.prlimit.nofile: 1048576 が必要

# 設定されていない場合
pct stop 200
cat >> /etc/pve/lxc/200.conf << 'EOF'
lxc.prlimit.nofile: 1048576
EOF
pct start 200
```

## 設定ファイル

| ファイル | 説明 |
|----------|------|
| `hosts/rin/default.nix` | NixOS設定（LXC、Podman、ファイアウォール） |
| `home-manager/narinari/rin.nix` | Home Manager設定（CLI、LLM、emacs-nox） |
| `flake.nix` | rin-lxc テンプレート、deploy-rs ノード定義 |
| `/etc/pve/lxc/200.conf` | Proxmox LXC設定（ホスト側） |

## ポート

| ポート | 用途 |
|--------|------|
| 22 | SSH |
| 3000-3100 | 開発サーバー（フロントエンド等） |
| 8000-8100 | 開発サーバー（API等） |
