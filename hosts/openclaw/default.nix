{
  pkgs,
  inputs,
  ...
}:
let
  openclaw = inputs.nix-openclaw.packages.x86_64-linux.default;
in
{
  imports = [
    ../common/linux/locale.nix
  ];

  # Proxmox LXC基本設定
  boot.isContainer = true;

  # Nix設定（LXC用）
  nix.settings.sandbox = false;

  # 基本ツール
  environment.systemPackages = with pkgs; [
    git
    curl
  ];

  # ユーザー設定
  users = {
    users = {
      root.openssh.authorizedKeys.keys = [
        (builtins.readFile ../../home-manager/narinari/id_ed25519.pub)
      ];
      openclaw = {
        isNormalUser = true;
        home = "/var/lib/openclaw";
        createHome = true;
        group = "openclaw";
        extraGroups = [ "wheel" ];
        openssh.authorizedKeys.keys = [
          (builtins.readFile ../../home-manager/narinari/id_ed25519.pub)
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

    # 永続化ディレクトリの準備（lost+foundはext4で自動作成されるため除外）
    preStart = ''
      mkdir -p /var/lib/openclaw/.openclaw
      chown openclaw:openclaw /var/lib/openclaw
      find /var/lib/openclaw -mindepth 1 ! -name 'lost+found' -exec chown -R openclaw:openclaw {} +
    '';

    environment = {
      HOME = "/var/lib/openclaw";
      OPENCLAW_STATE_DIR = "/var/lib/openclaw/.openclaw";
    };

    serviceConfig = {
      Type = "simple";
      User = "openclaw";
      Group = "openclaw";
      WorkingDirectory = "/var/lib/openclaw";

      # Discord Bot tokenは環境変数で管理
      # "-"プレフィックスでファイルが存在しない場合もエラーにならない
      EnvironmentFile = "-/var/lib/openclaw/.env";

      ExecStart = "${openclaw}/bin/openclaw gateway";
      Restart = "always";
      RestartSec = "10s";

      # セキュリティ設定
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = false; # OpenClawは/tmpに書き込む必要がある
      ReadWritePaths = [
        "/var/lib/openclaw"
        "/tmp"
      ];
    };
  };

  # SSH有効化（管理用）
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  # Avahi (mDNS)
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = false; # OpenClawが"openclaw"名でサービス公開できるようにする
    };
  };

  # ファイアウォール
  networking.firewall.allowedTCPPorts = [
    22
    18789
  ];

  system.stateVersion = "25.11";
}
