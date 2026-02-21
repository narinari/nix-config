{ pkgs, ... }:
{
  imports = [
    ../common/linux/locale.nix
  ];

  # Proxmox LXC基本設定
  boot.isContainer = true;

  # Nix設定（LXC用）
  nix.settings.sandbox = false;

  # ホスト名
  networking = {
    hostName = "jellyfin";
    # ファイアウォール
    firewall.allowedTCPPorts = [
      22 # SSH
      8096 # Jellyfin HTTP
      8920 # Jellyfin HTTPS
    ];
  };

  services = {
    # Jellyfin
    jellyfin = {
      enable = true;
      openFirewall = true;
    };

    # SSH有効化（管理用）
    openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
    };

    # Avahi（mDNS: jellyfin.local でアクセス可能に）
    avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };
  };

  # Intel QSV（ハードウェアトランスコード）
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # VAAPI driver for Intel N100
      intel-compute-runtime
    ];
  };

  users.users = {
    # jellyfinユーザーをvideo/renderグループに追加
    jellyfin.extraGroups = [
      "video"
      "render"
    ];
    # ユーザー設定
    root.openssh.authorizedKeys.keys = [
      (builtins.readFile ../../home-manager/narinari/id_ed25519.pub)
    ];
  };

  # メディア: Proxmoxホスト側でSambaをマウントし、bind mountでパススルー
  # /media はLXC設定（mp0）で提供されるため、NixOS側でのマウント設定は不要

  # 基本ツール
  environment.systemPackages = with pkgs; [
    git
    curl
  ];

  system.stateVersion = "25.11";
}
