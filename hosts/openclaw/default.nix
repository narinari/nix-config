{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ../common/linux/locale.nix
  ];

  # Proxmox LXC基本設定
  boot.isContainer = true;

  # Nix設定（LXC用）
  nix.settings.sandbox = false;

  # Node.js環境
  environment.systemPackages = with pkgs; [
    nodejs_22
    git
    curl
  ];

  # ユーザー設定
  users = {
    users = {
      root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICedOiRH96VIeFYIzMGPPCG2MLYhZkolBbl4wwtY8/A8 narinari.t@gmail.com"
        "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAy9qm4KNCA5rlPkdPlc+LMOSZvsXQxz271iq4C3ZMrR5mKkTXkCZPnLd0tizQOtG89+8MtTyWL9jNrxa2qKIy3DegHuy6YrVAlAQmsJ7dmAQ9SEKag71zibtdHvRbFjHPjmz+6VHUXS47kHM8P7DhQXDmVf5WRclq4xQqcN3EkxpYNVK95a+ifYtrks/yQqCADoo2RsttRZYEhcBVRHQDBLZGkXjH7Yam0smwpKaukMDErecJSEjlWzb7RVbTYs+NUfaFXnqdWmRDIzQX+brHbVkkhyHio124kw2A860L/qlk5+AKjX2q4wI5ULetavoaMPg1xdRzGQ/0gOhDN12UvQ== narinari.t@gmail.com"
      ];
      openclaw = {
        isNormalUser = true;
        home = "/var/lib/openclaw";
        createHome = true;
        group = "openclaw";
        extraGroups = [ "wheel" ];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICedOiRH96VIeFYIzMGPPCG2MLYhZkolBbl4wwtY8/A8 narinari.t@gmail.com"
          "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAy9qm4KNCA5rlPkdPlc+LMOSZvsXQxz271iq4C3ZMrR5mKkTXkCZPnLd0tizQOtG89+8MtTyWL9jNrxa2qKIy3DegHuy6YrVAlAQmsJ7dmAQ9SEKag71zibtdHvRbFjHPjmz+6VHUXS47kHM8P7DhQXDmVf5WRclq4xQqcN3EkxpYNVK95a+ifYtrks/yQqCADoo2RsttRZYEhcBVRHQDBLZGkXjH7Yam0smwpKaukMDErecJSEjlWzb7RVbTYs+NUfaFXnqdWmRDIzQX+brHbVkkhyHio124kw2A860L/qlk5+AKjX2q4wI5ULetavoaMPg1xdRzGQ/0gOhDN12UvQ== narinari.t@gmail.com"
        ];
      };
    };
    groups.openclaw = { };
  };

  # OpenClawサービス定義
  systemd.services.openclaw = {
    description = "OpenClaw AI Assistant";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    # 永続化ディレクトリの準備
    preStart = ''
      mkdir -p /var/lib/openclaw/.openclaw
      chown -R openclaw:openclaw /var/lib/openclaw
    '';

    serviceConfig = {
      Type = "simple";
      User = "openclaw";
      Group = "openclaw";
      WorkingDirectory = "/var/lib/openclaw";

      # Discord Bot tokenは環境変数で管理
      # "-"プレフィックスでファイルが存在しない場合もエラーにならない
      EnvironmentFile = "-/var/lib/openclaw/.env";

      ExecStart = "${pkgs.nodejs_22}/bin/npx -y openclaw";
      Restart = "always";
      RestartSec = "10s";

      # セキュリティ設定
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/openclaw" ];
    };
  };

  # SSH有効化（管理用）
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  # ファイアウォール
  networking.firewall.allowedTCPPorts = [ 22 ];

  system.stateVersion = "25.11";
}
