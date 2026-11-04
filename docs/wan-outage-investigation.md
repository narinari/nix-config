# WAN 断 (朝夕) の原因切り分け — 調査記録と監視構成

対象: 自宅 LAN (RTX810 Rev.11.01.34 / IIJmio ひかり + transix DS-Lite / **VDSL: NTT VH-100 4 E S**)
症状: 毎日 07–08 時と 18–19 時頃にインターネットが繋がりにくくなる。
初回調査: 2026-11-04 (khali から読み取りのみ)。

## 1. 確定した事実 (2026-11-04 時点)

| 項目 | 内容 |
|---|---|
| 回線 | VDSL (VH-100 4 E S) → RTX810 LAN2。上限 100 Mbps。LAN2 が 100BASE-TX でリンクするのは正常 |
| 障害の時系列 | khali journal 30 日分 (tailscaled の失敗と hermes の DNS 失敗という独立した 2 シグナル) で 33 エピソード。ほぼ毎日 07:10–08:20 (20–50 分) と 17:00–18:40 (10–25 分)、まれに 10:00–10:30 / 21–23 時。週末は 08:40–09:50 に遅れる |
| 故障範囲 | エピソード中は IPv4 (DS-Lite 経由の DNS→8.8.8.8) と IPv6 (ネイティブ tcp6→Tailscale controlplane/DERP) が同時に失敗。tailscaled NetInfo も一時 `ipv6=false udp=false icmpv4=false`。→ AFTR 単独ではなく RTX810 WAN 以下 (VDSL / NGN / transix IPoE GW) の断 |
| カナリア端末 | 192.168.100.6 `tg7100c` (MAC 84:3e:1d:8a:4a:69 = Hui Zhou Gaoshengda 製モジュール、Alibaba Cloud 47.236.42.97:1883 (MQTT) のみに接続) が 33 エピソード中 32 で DHCP 再取得 (他端末は 0)。クラウド断 → Wi‑Fi 再接続という IoT の挙動で、**結果であって原因ではない** |
| RTX810 の状態 | CPU 1–11%、Memory 8%、tunnel 1 は 2026-04-09 から連続 Online、LAN1 Receive overflow 4,332,680 / LAN2 30,301 (累積)、LAN2 link down のログ無し。VDSL 再トレーニングではモデムの Ethernet は落ちないので RTX からは見えない |
| 現在の基準値 | RTX LAN 0.3 ms / NGN 端 `2409:10:ae00:6400::fffe` 4.7 ms / transix v6 GW `2404:8e00:feed:ff1c::2` / AFTR v6 `2404:8e00::feed:100` 4.3 ms / AFTR v4 側 `14.0.9.197` 4.9 ms。v4 PMTU 1460 (RTX が ICMP Frag-Needed を正しく返す)、v6 PMTU 1500 |
| khali の DNS | resolved に eno1 の DNS が入らず (dhcpcd 連携不全)、FallbackDNS 8.8.8.8/1.1.1.1 を IPv4 (DS-Lite) 経由でのみ使用していた。v4 だけ落ちると名前解決が全滅する → IPv6 resolver を追加 (本リポジトリで修正) |
| RTX810 の DNS | EDNS 非対応で `+edns=0` に FORMERR。LAN 端末が router DNS を使うと大きな応答で問題になりうる (時間帯依存ではない) |

経路 (2026-11-04 09 時台):

```
v4: khali → 192.168.100.1 (pmtu 1460) → 14.0.9.197 (ike-cr000.transix.jp) → 210.173.176.127 → 103.22.201.123 → …
v6: khali → 2409:10:ae00:6400::1 → 2409:10:ae00:6400::fffe (NGN) → … → 2404:8e00:feed:ff1c::2 (transix) → 2001:7fa:7:1:… (JPIX) → Cloudflare
```

## 2. 仮説 (優先順) — 2026-11-04 13:20 更新

**判明したこと**: VDSL 区間は**上り負荷に弱い**。khali の qBittorrent が 5,000–7,000 pps (7–8 Mbit/s、
平均 175 バイトの小さな UDP) を送っている間は `::fffe` が 38 ms / 2–22% ロスに劣化し続け (12:24–13:17、
RTX CPU 30–45%)、12:43 と 12:47 に再トレーニング (LINE ランプ点滅、100% 断) に至った。
qBittorrent 停止 (13:16:58) の 1 分後に 4.8 ms / 0% / CPU 0% へ回復。
ただしユーザー申告により症状は qBittorrent 導入 (2026-09-24) 以前から存在するため、qBittorrent は
**根本原因ではなく再現性のある負荷の一例**。朝夕の引き金は他端末の上り (例: 10:34 に khali 以外から
34 Mbit/s の上りがあり `::fffe` が 25–50 ms になった) と考えられる。

1. **VDSL 回線が上り負荷で崩れる** (線路品質・上り同期速度・ノイズマージン不足) — 本命。宅内の上り
   (スマホのバックアップ、torrent、同期系) が朝夕に重なる
2. 集合装置側の混雑/ノイズ (負荷と無関係に劣化する時間帯があれば) — 継続観測で判定
3. transix IPoE GW / NGN の輻輳 — `::fffe` が正常で先だけ悪化する形で出るはず (今日は未観測)
4. RTX810 の処理飽和 — セッション 1,700 で CPU 30–45% まで上がるが、断の主因ではない (副次要因)

## 3. 監視構成

- khali `hosts/khali/net-monitor.nix`: node (9002) / smokeping (9374) / blackbox (9115) / snmp (9116) exporter と `udp514-journal` (RTX syslog 受信)
- friday `hosts/friday/default.nix`: Prometheus の scrape job (`khali-node`, `khali-smokeping`, `khali-blackbox`, `rtx810-snmp`) と Grafana ダッシュボード `WAN Health` (`hosts/friday/dashboards/wan-health.json`)
- RTX810: `snmpv2c host 192.168.100.14 rtxmon` / `snmp yriftunneldisplayatmib2 on` / `syslog host 192.168.100.14` / `syslog info on` (`docs/rtx810-config.txt` に反映)

smokeping のターゲットと意味:

| ターゲット | 区間 |
|---|---|
| 192.168.100.1 | RTX810 自身 (LAN) |
| 2409:10:ae00:6400::fffe | VDSL を越えた NGN 端ルーター |
| 2001:7fa:7:1:0:1:3335:1 | transix を抜けた直後の JPIX ホップ (transix GW `2404:8e00:feed:ff1c::2` は echo 非応答のため代替) |
| 2404:8e00::feed:100 | transix AFTR (IPv6 側) |
| 14.0.9.197 | AFTR の IPv4 側 = DS-Lite トンネル経由 |
| 1.1.1.1 / 8.8.8.8 | 外部 IPv4 (DS-Lite 経由) |
| 2606:4700:4700::1111 / 2001:4860:4860::8888 | 外部 IPv6 (ネイティブ) |

RTX の syslog は khali で `journalctl SYSLOG_IDENTIFIER=192.168.100.1` (unit は `udp514-journal.service`) で khali 側ログと同じ時刻軸で参照できる。確認済 (2026-11-04 10:10、`Login succeeded for SSH` が到達)。

## 4. 判定表 (エピソード中の観測 → 結論 → 次の行動)

| 観測 | 結論 | 次の行動 |
|---|---|---|
| RTX LAN ping OK、`::fffe` から先が全滅、RTX CPU 低 | VDSL/NGN アクセス区間 | モデムの LED (VDSL LINK 点滅 = 再トレーニング) を目視、NTT 113 の回線試験、電話線の分岐・ノイズ源の点検、管理組合に VDSL 集合装置の状況・光配線化を確認、IIJ/NTT に時刻付きで申告 |
| `::fffe` OK、transix GW / AFTR / 外部が失敗 | transix 側 | IIJ サポートに smokeping の時刻付きデータで申告。暫定で PPPoE 併用テスト |
| RTX CPU ≥ 80% または LAN2 ≈ 90 Mbps と同期 | 帯域飽和 / RTX 処理飽和 | `show ip connection` と node/snmp で重い端末を特定、RTX QoS や端末側スケジュール調整 |
| RTX LAN ping まで失敗 | RTX810 自身 | syslog/CPU を確認、再起動・ファーム・機器更新を検討 |

## 5. `tg7100c` (192.168.100.6) の特定方法

候補 (2026-11-04 ユーザー申告): **猫用自動トイレ CATLINK SCOOPER SE Standard**。CATLINK は杭州の
メーカーで、TG7100C (Ai-Thinker TG-12F 系、AliOS Things) + Alibaba Cloud IoT (MQTT) という構成と整合する。
モーターを持つ機器なので、WAN 断の「カナリア」であると同時に、稼働時の電気ノイズが VDSL (電話線) に
乗る「原因」である可能性もある (配置が電話線・モデム・同一コンセントに近い場合)。確定には下記 2〜3 と、
アプリから手動清掃を起動した瞬間の `::fffe` RTT/ロスを見る実験が有効。

実験結果 (2026-11-04 10:47–10:48、アプリから手動清掃): RTX LAN / `::fffe` / 1.1.1.1 / SCOOPER 自身への
0.2 秒間隔 ping 450 発すべて **ロス 0%、`::fffe` avg 4.7 ms (max 6.4 ms)**、RTX CPU 0–2%、LAN2 ifInErrors 0。
SCOOPER 自身の Wi‑Fi も途切れなかった。→ **清掃動作そのものは WAN に影響しない**。DHCP 再取得は WAN 断の
結果 (カナリア) という解釈を維持する。ユーザー確認 (同日): 電源はモデムと別系統、モデムから直線 2.5 m、
SCOOPER の動作ログにも障害時刻の稼働記録なし → **原因候補から除外**。以後は RTX ログの
`[DHCPD] ... Allocates 192.168.100.6` を障害時刻の指標として使う。


1. スマホの家電アプリ (Alibaba Cloud IoT を使う国内ブランドの家電・照明・空調等) のデバイス情報で MAC `84:3e:1d:8a:4a:69` を照合
2. 疑わしい機器の電源を順に抜き、`ping 192.168.100.6` の応答消失で確定
3. RTX で `show ip connection` を見て `47.236.42.97:1883` のセッションが消えることで確認

## 6. RTX810 への読み取りアクセス手順

- `ssh -o KexAlgorithms=+diffie-hellman-group14-sha1 -c aes256-ctr -o HostKeyAlgorithms=+ssh-rsa narinari@192.168.100.1`
- パスワードはリポジトリ直下の `rtx810_password.txt` (git 管理外)。`nix shell nixpkgs#sshpass -c sshpass -f rtx810_password.txt ssh ...` で渡す
- exec チャネル非対応 (`Channel request 'exec' is not supported`) → `-tt` で対話セッションを開き stdin にコマンドを流す
- `---more---` の改ページはスペース送出で進める (長い `show log` は 300〜400 回)
- 役に立った show コマンド: `show environment` (CPU/メモリ)、`show status lan1|lan2` (Receive overflow、リンク速度)、`show status tunnel 1`、`show status ipv6 dhcp`、`show ipv6 route`、`show ip connection` (端末ごとのセッション)、`show ipv6 neighbor cache`、`show log`

## 7. 観測結果 (追記欄)

| 日付 | エピソード | RTX LAN | ::fffe | transix GW | AFTR | 外部 v4 | 外部 v6 | RTX CPU / LAN2 bps | 判定 |
|---|---|---|---|---|---|---|---|---|---|
| 11-04 | 12:24–13:17 劣化、12:43–12:45 / 12:47–12:48 全断 (LINE ランプ点滅を目視) | 0.27 ms / 0% | 38 ms / 2–22%、断時 100% | 同左 | 同左 | 同左 | 同左 | CPU 30–45% / 上り 7–10 Mbit/s (khali qBittorrent 5–7k pps) | VDSL 区間 (上り負荷で劣化 → 再トレーニング) |
| 11-04 | 13:17 qBittorrent 停止実験 | 0% | 1 分後に 4.8 ms / 0% | 同左 | 同左 | 同左 | 同左 | CPU 0–2% / 上り 0 | 上り負荷が劣化の直接要因と確認 |
