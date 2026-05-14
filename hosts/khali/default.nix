{
  config,
  lib,
  pkgs,
  inputs,
  outputs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./hermes-agent.nix
    ./searxng.nix
    ../common/global
    ../common/linux
    ../common/linux/home-network.nix
    ../common/users/narinari
  ];

  networking.hostName = "khali";

  # systemd-boot (Arch Linux の ESP を共有)
  # NVIDIA modesetting が Wayland (Hyprland) に必要
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 5;
      };
      efi.canTouchEfiVariables = true;
      efi.efiSysMountPoint = "/boot";
    };
    kernelParams = [ "nvidia-drm.modeset=1" ];
    # / は xfs (nvme0n1p5)。initrd でも xfs を mount できるよう必須。
    supportedFilesystems.xfs = true;
    initrd.supportedFilesystems.xfs = true;
  };

  # Intel iGPU (プライマリ表示) + NVIDIA PRIME オフロード
  # 実機で `lspci | grep -E "VGA|3D"` を実行してBus IDを確認・更新すること
  # 例: "00:02.0 VGA" → "PCI:0:2:0", "01:00.0 3D" → "PCI:1:0:0"
  hardware = {
    nvidia = {
      modesetting.enable = true;
      open = false; # プロプライエタリカーネルモジュールを使用
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
      prime = {
        offload = {
          enable = true;
          enableOffloadCmd = true; # `nvidia-offload <cmd>` でNVIDIA使用可能
        };
        intelBusId = "PCI:0:2:0"; # ★ 要確認: lspci | grep -E "VGA|3D"
        nvidiaBusId = "PCI:1:0:0"; # ★ 要確認: lspci | grep -E "VGA|3D"
      };
    };
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        intel-media-driver # Intel VAAPI (Broadwell以降)
        libva-vdpau-driver
        libvdpau-va-gl
      ];
    };
  };

  # jarvisのSamba共有をマウント
  fileSystems."/mnt/tanabe-media" = {
    device = "//jarvis.local/tanabe-media";
    fsType = "cifs";
    options =
      let
        automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";
      in
      [
        "${automount_opts},iocharset=utf8,uid=narinari,gid=wheel,guest,nosetuids,noperm,rw"
      ];
  };

  # jarvisのNFS共有をマウント
  fileSystems."/mnt/nas" = {
    device = "jarvis.local:/fx-trading";
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=60"
      "x-systemd.device-timeout=5s"
      "x-systemd.mount-timeout=5s"
      "nfsvers=4"
    ];
  };

  programs = {
    # Hyprland (Wayland コンポジタ)
    hyprland = {
      enable = true;
      xwayland.enable = true;
      withUWSM = true; # uwsm 経由で起動 (systemd セッション管理)
    };
    # niri (Wayland scrollable-tiling コンポジタ) — Hyprland と併存。
    # tuigreet のセッション選択でどちらかを起動する。
    niri.enable = true;
    uwsm.enable = true; # UWSM の systemd 統合 (xdg-desktop-autostart.target を有効化)
    dconf.enable = true;
    ssh.startAgent = true;
  };

  # noctalia (Quickshell ベースのデスクトップシェル) の binary cache。
  # Quickshell のローカルビルドを回避するため。
  nix.settings = {
    substituters = [ "https://noctalia.cachix.org" ];
    trusted-public-keys = [ "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=" ];
  };

  # NixOS 統合の home-manager にも noctalia の HM module を渡す
  # (hosts/common/users/narinari で home-manager.users.narinari に
  #  khali.nix を import しているため、ここで sharedModules を渡す必要がある)。
  home-manager.sharedModules = [
    inputs.noctalia.homeModules.default
  ];

  # Intel iGPU primary + NVIDIA PRIME offload 用セッション変数
  environment.sessionVariables = {
    LD_LIBRARY_PATH = "/run/opengl-driver/lib"; # pip版PyTorch等がlibcuda.soを見つけるために必要
    LIBVA_DRIVER_NAME = "iHD"; # Intel iGPU ハードウェアアクセラレーション
    XDG_SESSION_TYPE = "wayland";
    WLR_NO_HARDWARE_CURSORS = "1"; # NVIDIA接続時のカーソル問題を回避
    NIXOS_OZONE_WL = "1"; # Chromium/Electron系アプリのWaylandネイティブ化
    QT_QPA_PLATFORMTHEME = "qt6ct"; # Qtアプリのテーマ設定
  };

  services = {
    # systemd-resolved を有効化
    # tailscaled が /etc/resolv.conf を 100.100.100.100 で書き潰す問題を回避するため。
    # resolved があると tailscaled は D-Bus 経由で tailscale0 link に MagicDNS を
    # split DNS で登録し、DHCP 由来の DNS (RTX810 = 192.168.100.1) と共存できる。
    # 参考: https://wiki.nixos.org/wiki/Tailscale, Tailscale FAQ "dns-resolv-conf"
    resolved = {
      enable = true;
      settings.Resolve = {
        DNSSEC = false; # RTX810 が EDNS 非対応のため
        FallbackDNS = [
          "1.1.1.1"
          "8.8.8.8"
        ];
      };
    };

    # Tailscale VPN
    tailscale.enable = true;

    # PulseAudio を無効化 (PipeWire を使うため)
    pulseaudio.enable = false;

    # programs.niri が xdg.portal に gnome portal を、また gnome-keyring も
    # 自動で有効化する。gnome-keyring は gcr-ssh-agent を引き入れ、これが
    # programs.ssh.startAgent と衝突する。SSH agent は openssh 側を維持したい
    # ため、gcr-ssh-agent だけ明示 off にする。
    gnome.gcr-ssh-agent.enable = false;

    # Intel iGPU をプライマリに設定
    xserver.videoDrivers = [
      "modesetting"
      "nvidia"
    ];

    # ディスプレイマネージャー (greetd + tuigreet)
    # --cmd niri-session: 初回・無選択時のデフォルトを niri に固定
    # --remember-user-session: ユーザーが切り替えた場合は記憶 (次回以降は記憶優先)
    greetd = {
      enable = true;
      settings.default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-user-session --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions --cmd niri-session";
        user = "greeter";
      };
    };

    # サウンド (PipeWire)
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    # sops の openssh 設定を上書き (初回インストール時: my-secrets に khali のキーがないため)
    # インストール後、SSH ホストキーを my-secrets に追加したら下記を削除して openssh.nix の設定を使うこと
    openssh.hostKeys = lib.mkForce [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  # tailscaled は admin DNS panel から push される split DNS (ts.net → 199.247.155.53)
  # を systemd-resolved に登録するが、199.247.155.53 は Tailscale 公開 anycast resolver で
  # 本 tailnet の MagicDNS レコードを持たない (SOA のみ返す)。
  # その結果 `ai` や他の tailnet ホストの名前解決が NXDOMAIN になり、Hermes が
  # http://ai/v1 にアクセスできなくなる。
  #
  # 対処: tailscaled がローカルで bind している stub (100.100.100.100) に向け直す。
  #   - oneshot service が tailscaled 起動後に resolvectl で link 単位の DNS を上書き
  #   - path watcher が resolv.conf 変化を契機に再適用 (tailscaled は netmap 更新で
  #     D-Bus 経由の push を再送するため)
  systemd.services.tailscale-dns-override = {
    description = "Override tailscale0 DNS to use local Tailscale stub (100.100.100.100)";
    after = [
      "tailscaled.service"
      "systemd-resolved.service"
    ];
    bindsTo = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
    };
    path = [
      pkgs.systemd
      pkgs.iproute2
    ];
    script = ''
      set -eu
      # tailscale0 link が現れるまで待つ
      for _ in $(seq 1 30); do
        if ip link show tailscale0 >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done
      resolvectl dns tailscale0 100.100.100.100
      resolvectl domain tailscale0 '~ts.net' 'taild10c60.ts.net'
    '';
  };

  systemd.paths.tailscale-dns-override = {
    description = "Re-apply tailscale DNS override when resolved config changes";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathChanged = "/run/systemd/resolve/resolv.conf";
      Unit = "tailscale-dns-override.service";
    };
  };

  # 日本語入力 (fcitx5 + SKK)
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      waylandFrontend = true; # Wayland ネイティブ入力プロトコル
      addons = with pkgs; [
        fcitx5-skk
        fcitx5-gtk
      ];
    };
  };

  security.rtkit.enable = true;

  # ファイアウォール
  networking.firewall = {
    allowedTCPPorts = [ 22 ];
    allowedUDPPorts = [ config.services.tailscale.port ]; # Tailscale WireGuard
    trustedInterfaces = [ "tailscale0" ]; # tailnet 内トラフィックを許可
  };

  sops.secrets = lib.mkForce { };

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.05";
}
