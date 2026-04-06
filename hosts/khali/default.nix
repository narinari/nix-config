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
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot";
  # NVIDIA modesetting が Wayland (Hyprland) に必要
  boot.kernelParams = [ "nvidia-drm.modeset=1" ];

  # Intel iGPU (プライマリ表示) + NVIDIA PRIME オフロード
  # 実機で `lspci | grep -E "VGA|3D"` を実行してBus IDを確認・更新すること
  # 例: "00:02.0 VGA" → "PCI:0:2:0", "01:00.0 3D" → "PCI:1:0:0"
  hardware.nvidia = {
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

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver # Intel VAAPI (Broadwell以降)
      vaapiVdpau
      libvdpau-va-gl
    ];
  };

  # Intel iGPU をプライマリに設定
  services.xserver.videoDrivers = [ "modesetting" "nvidia" ];

  # Hyprland (Wayland コンポジタ)
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # Intel iGPU primary + NVIDIA PRIME offload 用セッション変数
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD"; # Intel iGPU ハードウェアアクセラレーション
    XDG_SESSION_TYPE = "wayland";
    WLR_NO_HARDWARE_CURSORS = "1"; # NVIDIA接続時のカーソル問題を回避
    NIXOS_OZONE_WL = "1"; # Chromium/Electron系アプリのWaylandネイティブ化
  };

  # ディスプレイマネージャー (greetd + tuigreet)
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd Hyprland";
      user = "greeter";
    };
  };

  # 日本語入力 (fcitx5-mozc)
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-mozc
      fcitx5-gtk
    ];
  };

  # サウンド (PipeWire)
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;

  # ファイアウォール
  networking.firewall = {
    allowedTCPPorts = [ 22 ];
  };

  # sops の openssh 設定を上書き (初回インストール時: my-secrets に khali のキーがないため)
  # インストール後、SSH ホストキーを my-secrets に追加したら下記を削除して openssh.nix の設定を使うこと
  services.openssh.hostKeys = lib.mkForce [
    {
      path = "/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
  sops.secrets = lib.mkForce { };

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.05";
}
