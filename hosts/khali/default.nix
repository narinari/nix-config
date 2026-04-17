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
    pulseaudio.enable = false;
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
    dconf.enable = true;
    ssh.startAgent = true;
  };

  # Intel iGPU primary + NVIDIA PRIME offload 用セッション変数
  environment.sessionVariables = {
    LD_LIBRARY_PATH = "/run/opengl-driver/lib"; # pip版PyTorch等がlibcuda.soを見つけるために必要
    LIBVA_DRIVER_NAME = "iHD"; # Intel iGPU ハードウェアアクセラレーション
    XDG_SESSION_TYPE = "wayland";
    WLR_NO_HARDWARE_CURSORS = "1"; # NVIDIA接続時のカーソル問題を回避
    NIXOS_OZONE_WL = "1"; # Chromium/Electron系アプリのWaylandネイティブ化
    QT_QPA_PLATFORMTHEME = "qt6ct"; # Qtアプリのテーマ設定
    # fcitx5 日本語入力
    GTK_IM_MODULE = "fcitx";
    QT_IM_MODULE = "fcitx";
    XMODIFIERS = "@im=fcitx";
    SDL_IM_MODULE = "fcitx";
  };

  services = {
    # Tailscale VPN
    tailscale.enable = true;

    # Intel iGPU をプライマリに設定
    xserver.videoDrivers = [
      "modesetting"
      "nvidia"
    ];

    # ディスプレイマネージャー (greetd + tuigreet)
    greetd = {
      enable = true;
      settings.default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions";
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

  # 日本語入力 (fcitx5-mozc)
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-skk
      fcitx5-gtk
    ];
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
