# RTX810 IPv6 配布 + qBittorrent ポート開放 runbook

対象: RTX810 Rev.11.01.34 (IIJmio ひかり + transix DS-Lite)
目的: NGN の RA プレフィックスを LAN (lan1) に配布し、khali の qBittorrent
(ポート 50413/tcp+udp) だけを IPv6 inbound で許可する。

## 前提と安全設計

- **管理アクセスは LAN 側 IPv4** (`telnet 192.168.100.1`)。WAN/IPv6 側の設定を
  壊しても管理接続は失われず、常にロールバック可能。
- **作業順序が重要**: filter 定義 (無影響) → lan2 secure filter 適用 →
  IPv4 疎通確認 → lan1 へ RA 配布。
  逆順にすると、LAN ホストがグローバル IPv6 を取得してから filter が入るまでの
  無防備な時間ができる。
- **`save` は全検証が通ってから**。save 前なら電源再投入で完全に元へ戻る。
- DS-Lite の IPv4 は lan2 上の IPIP トンネル (protocol 4, AFTR 2404:8e00::feed:100)
  に乗っている。**これを遮断すると IPv4 が全断する**。filter 101001 は
  `pass * * 4` と広く許可し、AFTR アドレス再割当にも耐える形にする
  (絞りたくても 2404:8e00::/32 単位まで)。

## Step 0: 現状バックアップ

```
administrator
show config
```

出力全文を khali 上に保存する (例: `~/rtx810-config-backup-YYYYMMDD.txt`)。

## Step 1: フィルタ定義 (この時点では未適用なので無影響)

```
ipv6 filter 101000 pass * * icmp6 * *
ipv6 filter 101001 pass * * 4
ipv6 filter 101002 pass * ra-prefix@lan2::/64 tcp * 50413
ipv6 filter 101003 pass * ra-prefix@lan2::/64 udp * 50413
ipv6 filter 101099 pass * * * * *
ipv6 filter dynamic 101080 * * ftp
ipv6 filter dynamic 101081 * * domain
ipv6 filter dynamic 101082 * * www
ipv6 filter dynamic 101083 * * tcp
ipv6 filter dynamic 101084 * * udp
```

- 101000 (icmp6 全 pass) は ND/RA/PMTUD に必須。落とすと RA 受信ごと壊れる。
- 101001 は DS-Lite の生命線 (前述)。
- 101002/101003 の宛先 `ra-prefix@lan2::/64` が構文エラーになる場合は
  `show ipv6 address lan2` で実プレフィックスを確認し、リテラルで書く
  (その場合、NGN 側プレフィックス再割当時に手動更新が必要)。
- inbound の暗黙 deny は secure filter 適用時のリスト不一致破棄に任せる。

## Step 2: lan2 に secure filter 適用 (唯一の危険ポイント)

```
ipv6 lan2 secure filter in 101000 101001 101002 101003
ipv6 lan2 secure filter out 101099 dynamic 101080 101081 101082 101083 101084
```

**直後に必ず IPv4 疎通確認** (khali の別ターミナルで):

```bash
ping -c 3 1.1.1.1
curl -4 -s https://ifconfig.me   # CGN のグローバル IPv4 が返ること
```

ルーター側でも `show status tunnel 1` でトンネル up を確認。

**失敗時ロールバック (即時)**:

```
no ipv6 lan2 secure filter in
no ipv6 lan2 secure filter out
```

filter 定義 (101000〜) が残っても未適用なら無害。

## Step 3: lan1 への RA プレフィックス配布

```
ipv6 prefix 1 ra-prefix@lan2::/64
ipv6 lan1 address ra-prefix@lan2::1/64
ipv6 lan1 rtadv send 1 o_flag=off
```

- DHCPv6 server (`ipv6 lan1 dhcp service server`) は**設定しない**。
  RDNSS/DNS を配らないので LAN ホストの DNS 経路は IPv4 のまま
  = RTX810 の EDNS 非対応問題は発生しない。
- LAN の他機器 (非 NixOS 含む) も RA を受けて IPv6 を使い始める。
  問題が出たら下記ロールバックで即時に IPv4 のみへ戻せる。

**失敗時ロールバック**:

```
no ipv6 lan1 rtadv send
no ipv6 lan1 address ra-prefix@lan2::1/64
no ipv6 prefix 1
```

## Step 4: khali 側検証

```bash
ip -6 addr show dev eno1 scope global   # GUA (RFC7217 stable + temporary)
ip -6 route show default                 # via fe80::... dev eno1 proto ra
ping -6 -c 3 2001:4860:4860::8888
curl -6 -s https://ifconfig.co           # 自分の GUA が返る
sudo ip6tables -L nixos-fw -n | grep 50413   # TCP/UDP 両方あること
```

外部からの到達性 (いずれか):

- スマホを Wi-Fi OFF (モバイル回線 IPv6) にして Termux 等で
  `nc -6 -zv <khaliのGUA> 50413`
- IPv6 対応オンラインポートチェッカーで TCP 50413
- 外部の IPv6 ホストから `nmap -6 -p 50413 <GUA>`

qBittorrent の確認:

- WebUI (`http://khali.taild10c60.ts.net:8080`) で Ubuntu ISO 公式 torrent を追加
- ステータスバーが connectable (地球アイコン) になること
  (火柱 = firewalled のままなら NG)
- ピア一覧の IPv6 ピアに incoming (`I`) フラグが付く、DHT ノード数が増える
- IPv4 ピアとも DL/UL が進む (CGN 経由 passive 動作)

## Step 5: 確定

全検証 OK 後、ルーターで:

```
save
```

## Step 6 (任意・後日): ポートフィルタを khali 宛に絞る

初期は /64 全体宛を推奨。RFC7217 の IID はプレフィックスをハッシュ入力に
含むため、NGN 側の再割当で khali のアドレスごと変わり、リテラルで絞った
フィルタは黙って無効化される。開けているのは 1 ポートのみでリスクは小さい。

絞る場合は `ip -6 addr show dev eno1 scope global` で stable アドレスを確認し:

```
ipv6 filter 101002 pass * <khaliのGUA> tcp * 50413
ipv6 filter 101003 pass * <khaliのGUA> udp * 50413
```

(同番号での再定義は上書き。適用リストの変更は不要。)

## 運用メモ

- qBittorrent の設定は NixOS の `services.qbittorrent.serverConfig`
  (hosts/khali/qbittorrent.nix) が起動毎に上書きする。WebUI での変更は
  再起動で消えるため、恒久設定は Nix 側に書くこと。
- CGN セッション枯渇の兆候 (LAN 全体のブラウジング劣化) が出たら
  `show nat descriptor address` でセッション消費を確認し、
  serverConfig の `MaxConnections` (現在 200) をさらに下げる。
- sshd 等の他サービスは khali の firewall で開いていても、RTX810 の
  inbound filter が 50413 以外を deny するため外部からは到達不可。
