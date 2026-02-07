# OpenClaw LXC 運用ガイド

## 概要

- **ホスト名**: openclaw
- **CT ID**: 100
- **永続化**: CT Volume (`local-lvm:vm-100-disk-1`)
- **サービス**: systemd `openclaw.service`

## 日常運用

### サービス状態確認
```bash
pct exec 100 -- systemctl status openclaw
```

### ログ確認
```bash
pct exec 100 -- journalctl -u openclaw -f
```

### サービス再起動
```bash
pct exec 100 -- systemctl restart openclaw
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
pct exec 100 -- bash -c 'echo "DISCORD_BOT_TOKEN=new_token_here" > /var/lib/openclaw/.env && chmod 600 /var/lib/openclaw/.env && chown openclaw:openclaw /var/lib/openclaw/.env'
pct exec 100 -- systemctl restart openclaw
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
# ボリュームID確認
pct config 100 | grep mp0

# コンテナ停止・削除（ボリューム保持）
pct stop 100
pct destroy 100 --purge 0

# 新コンテナ作成
pct create 100 local:vztmpl/nixos-openclaw.tar.xz \
  --hostname openclaw \
  --memory 2048 \
  --cores 2 \
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
   pct exec 100 -- journalctl -u openclaw -n 50
   ```

2. 手動起動テスト
   ```bash
   pct exec 100 -- su - openclaw -c 'npx -y openclaw'
   ```

3. ネットワーク確認
   ```bash
   pct exec 100 -- ping -c 3 discord.com
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

- Discord Bot tokenは`.env`ファイルで管理（権限600）
- SSHはパスワード認証無効、鍵認証のみ
- ファイアウォールはSSH(22)のみ開放

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
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --features nesting=1 \
  --mp0 local-lvm:1,mp=/var/lib/openclaw,backup=1
```

- `local-lvm:1`: 1GBのボリュームを作成（必要に応じて調整）
- `backup=1`: Proxmoxバックアップに含める

### 4. Discord Bot token設定（初回のみ）
```bash
pct exec 100 -- bash -c 'echo "DISCORD_BOT_TOKEN=your_discord_bot_token_here" > /var/lib/openclaw/.env && chmod 600 /var/lib/openclaw/.env && chown openclaw:openclaw /var/lib/openclaw/.env'
```

### 5. コンテナ起動
```bash
pct start 100
```

## 参考資料

- [Discord - OpenClaw Docs](https://docs.openclaw.ai/channels/discord)
- [NixOS Wiki - Proxmox Linux Container](https://nixos.wiki/wiki/Proxmox_Linux_Container)
- [OpenClaw Installation Guide](https://www.aifreeapi.com/en/posts/openclaw-installation-guide)
- [Proxmox pct.conf Manual](https://pve.proxmox.com/wiki/Manual:_pct.conf)
