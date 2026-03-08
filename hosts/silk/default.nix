{
  config,
  lib,
  pkgs,
  inputs,
  outputs,
  ...
}:

let
  libarib25 = pkgs.callPackage ../../pkgs/libarib25 { };
  recpt1 = pkgs.callPackage ../../pkgs/recpt1 { inherit libarib25; };
  it930x-firmware = pkgs.callPackage ../../pkgs/it930x-firmware { };
  px4_drv = pkgs.callPackage ../../pkgs/px4_drv { inherit (config.boot.kernelPackages) kernel; };
  tuners = import ../../modules/services/mirakurun/tuner.nix { inherit recpt1; };
  channels = import ../../modules/services/mirakurun/channel.nix;
in
{
  imports = [
    ../rpi4-base
    ../common/home-server
  ];

  networking = {
    hostName = "silk";
    networkmanager.enable = lib.mkForce false;
  };

  # PX4 チューナードライバ
  boot.extraModulePackages = [ px4_drv ];
  boot.kernelModules = [ "px4_drv" ];

  # PX4ファームウェア（it930x-firmware.bin）
  hardware.firmware = [ it930x-firmware ];

  # WiFi PSK (sops-nix経由)
  sops.secrets.wifi-psk = {
    sopsFile = "${inputs.my-secrets}/private/service_secrets.yaml";
    key = "wifi-psk-Buffalo-A-41D0";
    mode = "0444";
  };

  # WiFi設定
  networking.wireless = {
    enable = true;
    interfaces = [ "wlan0" ];
    secretsFile = config.sops.secrets.wifi-psk.path;
    networks."Buffalo-A-41D0".pskRaw = "ext:wifi_psk_Buffalo_A_41D0";
  };

  services = {
    # Mirakurun TVチューナーサーバー
    mirakurun = {
      enable = true;
      openFirewall = true;
      serverSettings = {
        port = 40772;
        logLevel = 2;
      };
      tunerSettings = tuners;
      channelSettings = channels;
    };

    # スマートカードデーモン (B-CASカード用)
    pcscd.enable = true;

    # PX4チューナー用udevルール
    udev.extraRules = ''
      # PX4 tuner devices
      SUBSYSTEM=="video4linux", ATTRS{idVendor}=="0511", MODE="0666", GROUP="video"
      KERNEL=="px4video*", MODE="0666", GROUP="video"
    '';
  };

  # 必要なパッケージ
  environment.systemPackages = [
    recpt1
    libarib25
    pkgs.pcsc-tools
  ];

  # チューナーデバイスへのアクセス権限
  users.groups.video.members = [ "mirakurun" ];

  system.stateVersion = "23.11";
}
