{
  config,
  lib,
  pkgs,
  modulesPath,
  inputs,
  ...
}:

{
  imports = [
    "${toString modulesPath}/virtualisation/proxmox-lxc.nix"
    ../common/global
    ../common/linux
    ../common/linux/home-network.nix
    ../common/linux/nix-builder.nix
    ../common/users/narinari
  ];

  networking = {
    hostName = "rin";
    useNetworkd = true;
    useDHCP = false;
  };

  # eth0 DHCP設定
  systemd.network = {
    enable = true;
    networks."10-eth0" = {
      matchConfig.Name = "eth0";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "23.05";

  # LXC固有設定
  boot.isContainer = true;
  nix.settings.sandbox = false;

  # LXCではpam_limitsが動作しないため無効化
  # （ホスト側で lxc.prlimit.nofile を設定）
  security.pam.loginLimits = lib.mkForce [ ];

  # Podman（Docker互換、LXC親和性が高い）
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  # rinではsopsシークレットを無効化（host_keys.yamlにrinの鍵がないため）
  # sops.secretsをクリアするとopenssh.nixのhost-keys参照が壊れるためhostKeysもオーバーライド
  services.openssh.hostKeys = lib.mkForce [
    {
      path = "/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
  sops.secrets = lib.mkForce { };

  # ファイアウォール
  networking.firewall = {
    allowedTCPPorts = [ 22 ];
    allowedTCPPortRanges = [
      {
        from = 3000;
        to = 3100;
      } # 開発サーバー用
      {
        from = 8000;
        to = 8100;
      }
    ];
  };
}
