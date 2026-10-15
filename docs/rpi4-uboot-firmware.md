# RPi4 (jarvis / friday / silk) の U-Boot と firmware パーティションの宣言管理

## 症状

jarvis が U-Boot で次のエラーになり起動しない。

```
ERROR: rd image overlaps os image
Could not find a valid device tree
```

U-Boot コンソールから以下で一時的に起動できる (`fdt_addr` ではなく `fdt_addr_r`)。

```
setenv ramdisk_addr_r 0x27000000
setenv fdt_addr_r 0x26000000
boot
```

## 原因

- nixpkgs の `sd-image-aarch64.nix` は `sdImage.populateFirmwareCommands` で
  `u-boot-rpi4.bin` を FIRMWARE パーティションへ書くが、これは **SD イメージ作成時にしか実行されない**。
  `nixos-rebuild` / `deploy` は `/boot/extlinux` と `/boot/nixos` (ルート側) しか更新しない。
- 2023 年のイメージに入っていた U-Boot 2021.04 は `fdt_addr_r=0x02e00000`,
  `ramdisk_addr_r=0x02f00000`。U-Boot は Image を 0x200000 に展開するため、カーネルが約 44MB を超えると
  DTB / initrd の置き場所と重なる。
- nixpkgs 汎用 aarch64 カーネル Image は 2024 年以降 60MB 超が平常 (`DEBUG_INFO_BTF` 等)。
  jarvis の 6.19.11 は 64,129,536 B、次の 7.1.2 は 66,988,544 B。
- nixpkgs の U-Boot (2025.01 以降、infra lock では 2026.04) は上流 `board/raspberrypi/rpi/rpi.env` が
  `fdt_addr_r=0x05600000`, `ramdisk_addr_r=0x05700000` になっており、**約 84MB までの Image を扱える**。

2026-10-15 時点の実測:

| ホスト | ブート媒体 | FIRMWARE 上の U-Boot | fdt_addr_r / ramdisk_addr_r | 状態 |
|---|---|---|---|---|
| jarvis | mmcblk0p1 (30MiB vfat) | 2021.04 | 0x02e00000 / 0x02f00000 | 起動不能 → 手動 setenv で復旧中 |
| friday | sda1 (USB SSD, 30MiB vfat) | 2021.04 | 0x02e00000 / 0x02f00000 | 1043 日無再起動。次の再起動で同症状 |
| silk | mmcblk0p1 (30MiB vfat) | 2024-04 以降の nixpkgs patch 版 | 0x05700000 / 0x05800000 | 問題なし |

## 対応 (hosts/common/rpi4/default.nix)

nixos-hardware (2026-07-10 PR #1894 以降) の `hardware.raspberry-pi.firmware` を使い、
**switch ごとに activation script が `/boot/firmware` を再配置**する。

| オプション | 値 | 意味 |
|---|---|---|
| `hardware.raspberry-pi.firmware.enable` | `true` | activation で `start*.elf`, `fixup*.dat`, `bootcode.bin`, DTB/overlays, `config.txt` をコピー |
| `hardware.raspberry-pi.firmware.uboot.enable` | `true` | `pkgs.ubootRaspberryPiAarch64` の `u-boot.bin` をコピーし、`config.txt` に `kernel=u-boot.bin`, `arm_64bit=1` を設定 |
| `hardware.raspberry-pi.configtxt.settings.all.avoid_warnings` | `true` | 旧 sd-image の config.txt と同じ (mainline の framebuffer を壊さない) |
| `hardware.raspberry-pi.configtxt.settings.pi4.enable_gic` | `true` | 旧 config.txt と同じ。`armstub8-gic.bin` は firmware 内蔵 stub が GIC 対応のため不要 |
| `hardware.raspberry-pi.configtxt.deviceTreeOverlays.all` | `mkForce [ ]` | ヘッドレスなので vc4-kms-v3d 不要。FDTDIR で DTB を再ロードするため firmware 側 overlay は効かない |
| `boot.loader.generic-extlinux-compatible.useGenerationDeviceTree` | `true` | `uboot.enable` が mkDefault false にするが、従来の FDTDIR 方式 (カーネル同梱 DTB + `apply-overlays-dtmerge`) を維持 |
| `fileSystems."/boot/firmware".options` | `mkForce [ "nofail" "noatime" ]` | sd-image.nix は `noauto`。activation script は mountpoint でないとスキップするので常時マウント |

`sdImage.populateFirmwareCommands` も同モジュールが mkForce で置き換えるため、`rpi4-base` の SD イメージも同じ内容になる。

## 反映 runbook (順序: jarvis → silk → friday)

jarvis は復旧経路が確認済み、silk は U-Boot が既に新しく低リスク、friday は 6.1 → 7.1 で 3 年ぶりの再起動となり最もリスクが高い。

`<fw>`: jarvis / silk は `/dev/mmcblk0p1`、friday は `/dev/sda1`。

1. runbook を実機に書き出す (session 断に備える): `~/runbook-uboot-update.md`
2. FIRMWARE をバックアップ:
   ```sh
   sudo dd if=<fw> of=/root/firmware-backup-$(date +%Y%m%d).img bs=1M
   # 作業機にも: scp <host>.local:/root/firmware-backup-*.img ~/backups/<host>/
   ```
3. 初回だけ手動マウント (現状 noauto): `sudo mount /boot/firmware && findmnt /boot/firmware`
4. 事前確認 (作業機): `deploy .#<host> --dry-activate` (remoteBuild=true のため target 上でビルド)。
   silk は out-of-tree の px4_drv が新カーネルでビルドできるかをここで確認する。
5. 反映: `deploy .#<host>`
6. 検証 (再起動前):
   ```sh
   sudo strings -n 8 /boot/firmware/u-boot.bin | grep -E '^U-Boot 20|^(fdt_addr_r|ramdisk_addr_r)='
   #   → U-Boot 2026.04 / fdt_addr_r=0x05600000 / ramdisk_addr_r=0x05700000
   grep -E '^(kernel|arm_64bit|enable_uart|enable_gic|avoid_warnings)=' /boot/firmware/config.txt
   ls /boot/firmware/bcm2711-rpi-4-b.dtb /boot/firmware/start4.elf
   ls /boot/firmware/uboot.env 2>&1     # 存在しないこと (あれば新 U-Boot の既定値を上書きするので削除)
   grep -c FDTDIR /boot/extlinux/extlinux.conf   # > 0
   ```
7. 再起動 → `uname -r`、`findmnt /boot/firmware`、ホスト固有サービス
   (jarvis: samba / nfs / smartctl exporter、silk: `lsmod | grep px4_drv`、friday: 稼働サービス) を確認。
8. 任意: 旧ファイル `/boot/firmware/{u-boot-rpi4.bin,u-boot-rpi3.bin,armstub8-gic.bin}` を削除
   (activation script は DTB / overlays しか prune しない)。

### 実施時に判明した注意点 (2026-10-15)

- **switch inhibitor**: 26.05 → 26.11 のように dbus 実装が変わる更新では `deploy` (switch) が
  「Pre-switch check 'switchInhibitors' failed」で拒否されロールバックされる。
  `deploy .#<host> --boot --skip-checks` で次回起動用プロファイルだけ設定し、
  **firmware 配置スクリプトを手動で実行してから**再起動する (boot モードでは activation script が走らない)。
  ```sh
  T=$(nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.outPath)
  ssh <host> "grep -oE '/nix/store/[a-z0-9]{32}-install-rpi-firmware/bin/install-rpi-firmware' $T/activate | head -1"
  ssh <host> sudo /nix/store/...-install-rpi-firmware/bin/install-rpi-firmware /boot/firmware
  ```
- 起動時の activation では `/boot/firmware` がまだマウントされておらず「not a mounted partition, skipping」になる。
  firmware が更新されるのは `switch` 時だけ (想定どおり)。
- `deploy-rs` の `remoteBuild = true` は各ターゲットが自前でビルドするため、3 台が同じ derivation を別々に
  ビルドする。1 台 (jarvis) でビルドした後 `nix copy --from ssh-ng://narinari@jarvis.local --to ssh-ng://narinari@<host>.local --no-check-sigs <toplevel>`
  で閉包を配ると他ホストはホスト固有分のビルドだけで済む。
- `deploy` の事前 `nix flake check` は無関係なホスト (rin) の評価エラーでも止まるので `--skip-checks` を使う。
- home-manager global の GUI 版 Emacs (emacs-unstable-pgtk、キャッシュ無し) は RPi4 で数時間のビルドになる。
  サーバは `programs.emacs.terminal = true` (emacs-nox) にした。
- 26.11 / linux 7.1.2 では RPi4 の有線 NIC が `eth0` → `end0` (predictable name) に変わる。
  `interfaces = eth0` のような設定 (jarvis の samba) は要修正。
- jarvis では再起動後に md RAID (USB 接続 4 台、raid6) が自動で組まれなかった (md_mod 未ロード、/proc/mdstat 無し)。
  原因調査中。手動復旧は `mdadm --assemble --scan` → `vgchange -ay` → mount unit 起動。
- `deploy` 用 `etc/ssh.config` は mDNS 名を使う。再起動直後は avahi が上がらず `.local` が引けないことがあるので
  `deploy --hostname <IP>` で回避できる。

### フォールバック

- 新 U-Boot で起動しない: SD/SSD を作業機に挿し `dd if=firmware-backup-*.img of=<fw>` で FIRMWARE を丸ごと戻す。
  旧 U-Boot では従来どおりコンソールで `setenv fdt_addr_r 0x26000000; setenv ramdisk_addr_r 0x27000000; boot`。
- 新カーネル側の問題: U-Boot メニューで旧世代を選ぶ。U-Boot 更新は世代非依存なのでロールバック不要。

## 将来の検討メモ

### カーネルが 84MB を超えたら

`hardware.raspberry-pi.firmware.uboot.package` を override して `rpi.env` のアドレスを上げる (未検証)。

```nix
hardware.raspberry-pi.firmware.uboot.package = pkgs.ubootRaspberryPiAarch64.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    sed -i -e 's/^fdt_addr_r=.*/fdt_addr_r=0x07600000/' \
           -e 's/^ramdisk_addr_r=.*/ramdisk_addr_r=0x07700000/' \
           board/raspberrypi/rpi/rpi.env
  '';
});
```

あるいは `boot.kernelPackages = pkgs.linuxPackages_rpi4` (vendor カーネル、Image が小さい) へ変更する。
silk の px4_drv と DTB 運用への影響を確認してから。

### U-Boot を使わない方式 (不採用、別タスク)

- nixpkgs 本体の `boot.loader.raspberryPi` は削除済み (PR #356688)。nix-community/raspberry-pi-nix は archive 済み。
- 後継は [nvmd/nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi)。
  `boot.loader.raspberry-pi.bootloader = "kernel"` で firmware が `kernel.img` / `initrd` を直接ロードし、
  世代は `config.txt` の `os_prefix` 切替 (tryboot 連携なし)。
- 世代ごとに kernel + initrd + DTB (約 92MB) を FAT 側に置くため、同プロジェクトの sd-image は
  `sdImage.firmwareSize = 1024` (MiB)。既存の 30MiB FIRMWARE では **SD カードの作り直しが必須**で、
  今回は見送った。
