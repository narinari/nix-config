# OpenClaw LXC 運用ガイド

## 概要

- **ホスト名**: openclaw
- **CT ID**: 100
- **永続化**: CT Volume (`local-lvm:vm-100-disk-1`)
- **サービス**: systemd `openclaw.service`

## 日常運用

> **注意**: NixOS LXCでは`pct exec`でコマンドを実行する際、フルパスが必要です。
> SSHを使う場合は通常のコマンドが使えます: `ssh root@openclaw.local`

### サービス状態確認
```bash
# pct exec経由（フルパス必要）
pct exec 100 -- /run/current-system/sw/bin/systemctl status openclaw

# SSH経由（推奨）
ssh root@openclaw.local 'systemctl status openclaw'
```

### ログ確認
```bash
pct exec 100 -- /run/current-system/sw/bin/journalctl -u openclaw -f

# または
ssh root@openclaw.local 'journalctl -u openclaw -f'
```

### サービス再起動
```bash
pct exec 100 -- /run/current-system/sw/bin/systemctl restart openclaw
```

### コンテナ再起動
```bash
pct reboot 100
```

## バックアップ

### 手動バックアップ
```bash
vzdump 100 --storage local --mode snapshot
```

### スケジュールバックアップ
Proxmox UI → Datacenter → Backup で設定

### バックアップからリストア
```bash
pct restore 100 /var/lib/vz/dump/vzdump-lxc-100-*.tar.zst
```

## Discord Bot Token更新

```bash
# 既存の.envを編集（他の環境変数を保持）
ssh root@openclaw.local 'sed -i "s/^DISCORD_BOT_TOKEN=.*/DISCORD_BOT_TOKEN=new_token_here/" /var/lib/openclaw/.env'
ssh root@openclaw.local 'systemctl restart openclaw'
```

## NixOS構成更新

### 1. ローカルでビルド
```bash
cd ~/dev/src/github.com/narinari/nix-config
# 構成を編集
vim hosts/openclaw/default.nix

# ビルド
nix build .#openclaw-lxc
```

### 2. テンプレートをアップロード
```bash
scp result/tarball/nixos-system-x86_64-linux.tar.xz \
  proxmox:/var/lib/vz/template/cache/nixos-openclaw.tar.xz
```

### 3. コンテナ再作成（データ保持）
```bash
# ボリュームID確認・メモ
pct config 100 | grep mp0
# 例: mp0: local-lvm:vm-100-disk-1,mp=/var/lib/openclaw,backup=1

# コンテナ停止
pct stop 100

# 設定ファイルからmp0行を直接削除（ボリューム自体は保持される）
# 注意: pct set --delete mp0 はボリュームも削除してしまうため使用しない
sed -i '/^mp0:/d' /etc/pve/lxc/100.conf

# コンテナ削除
pct destroy 100

# ボリュームが保持されているか確認
pvesm list local-lvm | grep vm-100

# 新コンテナ作成（既存ボリュームを指定）
pct create 100 local:vztmpl/nixos-openclaw.tar.xz \
  --hostname openclaw \
  --memory 2048 \
  --cores 2 \
  --rootfs local-lvm:8 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --features nesting=1 \
  --mp0 local-lvm:vm-100-disk-1,mp=/var/lib/openclaw,backup=1

# 起動
pct start 100
```

## トラブルシューティング

### OpenClawが起動しない

1. ログ確認
   ```bash
   ssh root@openclaw.local 'journalctl -u openclaw -n 50'
   ```

2. 手動起動テスト
   ```bash
   ssh root@openclaw.local 'su - openclaw -c "$(grep ExecStart /etc/systemd/system/openclaw.service | cut -d= -f2)"'
   ```

3. ネットワーク確認
   ```bash
   ssh root@openclaw.local 'ping -c 3 discord.com'
   ```

### lost+found権限エラー

CT Volumeを使用する場合、ext4の`lost+found`ディレクトリでchownが失敗することがあります。

```
chown: cannot read directory '/var/lib/openclaw/lost+found': Permission denied
```

**解決策**:
```bash
ssh root@openclaw.local 'rm -rf /var/lib/openclaw/lost+found'
ssh root@openclaw.local 'systemctl restart openclaw'
```

### Gateway lockエラー

```
failed to acquire gateway lock at /tmp/openclaw-1000/gateway.*.lock
```

**解決策**:
```bash
ssh root@openclaw.local 'systemctl stop openclaw && rm -rf /tmp/openclaw-* && systemctl start openclaw'
```

### "Missing config" エラー

OpenClawの初期設定が完了していません。

```bash
# 設定を確認
ssh root@openclaw.local 'cat /var/lib/openclaw/.openclaw/openclaw.json'

# gateway.modeが未設定の場合
OPENCLAW_BIN=$(ssh root@openclaw.local 'grep ExecStart /etc/systemd/system/openclaw.service | cut -d= -f2 | cut -d" " -f1')
ssh root@openclaw.local "su - openclaw -c '$OPENCLAW_BIN config set gateway.mode local'"
ssh root@openclaw.local "su - openclaw -c '$OPENCLAW_BIN config set channels.discord.enabled true'"
```

### Discord Botが応答しない

1. Bot tokenが正しいか確認
   ```bash
   pct exec 100 -- cat /var/lib/openclaw/.env
   ```

2. Discord Developer Portalで:
   - Bot tokenが有効か確認
   - Message Content Intentが有効か確認
   - Botがサーバーに参加しているか確認

### ディスク容量不足

```bash
# 使用量確認
pct exec 100 -- df -h /var/lib/openclaw

# ボリューム拡張（Proxmoxホストで）
pct resize 100 mp0 +1G
```

## 監視

### Prometheusメトリクス（オプション）

`hosts/openclaw/default.nix`に追加:
```nix
services.prometheus.exporters.node = {
  enable = true;
  port = 9100;
  openFirewall = true;
};
```

既存のPrometheusに追加:
```yaml
- job_name: 'openclaw'
  static_configs:
    - targets: ['openclaw.local:9100']
```

## セキュリティ

- Discord Bot token、Anthropic API keyは`.env`ファイルで管理（権限600）
- SSHはパスワード認証無効、鍵認証のみ
- ファイアウォールはSSH(22)とGateway(18789)を開放

## 初回セットアップ

### 1. LXCテンプレートをビルド
```bash
cd ~/dev/src/github.com/narinari/nix-config
nix build .#openclaw-lxc
```

### 2. Proxmoxにアップロード
```bash
scp result/tarball/nixos-system-x86_64-linux.tar.xz \
  proxmox:/var/lib/vz/template/cache/nixos-openclaw.tar.xz
```

### 3. コンテナ作成（CT Volumeで永続化）
```bash
pct create 100 local:vztmpl/nixos-openclaw.tar.xz \
  --hostname openclaw \
  --memory 2048 \
  --cores 2 \
  --rootfs local-lvm:8 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --features nesting=1 \
  --mp0 local-lvm:1,mp=/var/lib/openclaw,backup=1
```

- `local-lvm:1`: 1GBのボリュームを作成（必要に応じて調整）
- `backup=1`: Proxmoxバックアップに含める

### 4. コンテナ起動
```bash
pct start 100
```

### 5. 環境変数設定（初回のみ）

`.env`ファイルに必要な環境変数を設定：

```bash
ssh root@openclaw.local 'cat > /var/lib/openclaw/.env << EOF
DISCORD_BOT_TOKEN=your_discord_bot_token_here
ANTHROPIC_API_KEY=your_anthropic_api_key_here
OPENCLAW_GATEWAY_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '+/=' | head -c 32)
EOF
chmod 600 /var/lib/openclaw/.env
chown openclaw:openclaw /var/lib/openclaw/.env
rm -rf /var/lib/openclaw/lost+found'
```

### 6. OpenClaw初期設定

```bash
# openclawバイナリのパスを確認
OPENCLAW_BIN=$(ssh root@openclaw.local 'grep ExecStart /etc/systemd/system/openclaw.service | cut -d= -f2 | cut -d" " -f1')

# Gateway modeとDiscordを有効化
ssh root@openclaw.local "su - openclaw -c '$OPENCLAW_BIN config set gateway.mode local'"
ssh root@openclaw.local "su - openclaw -c '$OPENCLAW_BIN config set channels.discord.enabled true'"

# サービス再起動
ssh root@openclaw.local 'systemctl restart openclaw'

# 動作確認
ssh root@openclaw.local 'journalctl -u openclaw -n 20'
```

## 参考資料

- [Discord - OpenClaw Docs](https://docs.openclaw.ai/channels/discord)
- [NixOS Wiki - Proxmox Linux Container](https://nixos.wiki/wiki/Proxmox_Linux_Container)
- [OpenClaw Installation Guide](https://www.aifreeapi.com/en/posts/openclaw-installation-guide)
- [Proxmox pct.conf Manual](https://pve.proxmox.com/wiki/Manual:_pct.conf)
