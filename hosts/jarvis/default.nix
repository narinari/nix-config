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
    ../rpi4-base
    ../common/home-server
    ../common/linux/nix-builder.nix
  ];

  networking = {
    hostName = "jarvis";
  };

  # Nix設定
  nix.envVars.TMPDIR = "/nix/tmp";
  systemd.services.nix-daemon.environment.TMPDIR = "/nix/tmp";

  systemd.tmpfiles.rules = [
    "d /nix/tmp 1777 root root 1d"
    "d /mnt/data/tanabe-media/fx-trading 0755 narinari users -"
  ];

  # 外部ディスクマウント・NFSエクスポート用バインドマウント
  fileSystems = {
    "/mnt/data/xxx" = {
      device = "/dev/disk/by-label/XDATA";
      fsType = "ext4";
      options = [ "nofail" ];
    };
    "/mnt/data/tanabe-media" = {
      device = "/dev/disk/by-label/tanabe-video";
      fsType = "ext4";
      options = [ "nofail" ];
    };
    "/export/xxx" = {
      device = "/mnt/data/xxx";
      fsType = "none";
      options = [
        "bind"
        "nofail"
      ];
    };
    "/export/fx-trading" = {
      device = "/mnt/data/tanabe-media/fx-trading";
      fsType = "none";
      options = [
        "bind"
        "nofail"
      ];
    };
  };

  # ファイアウォール
  networking.firewall.allowedTCPPorts = [
    111
    2049
    20048 # nfs
    5357 # wsdd
  ];
  networking.firewall.allowedUDPPorts = [
    3702 # wsdd
  ];

  services = {
    # Samba設定
    samba-wsdd.enable = true;
    samba = {
      enable = true;
      openFirewall = true;
      settings = {
        global = {
          workgroup = "WORKGROUP";
          "server string" = "tanabes-data";
          "netbios name" = "tanabes-data";
          security = "user";

          "server multi channel support" = "yes";
          deadtime = 30;
          "use sendfile" = "yes";
          "min receivefile size" = 16384;

          # パフォーマンスチューニング
          "aio read size" = 1048576;
          "aio write size" = 1048576;
          "smb2 max credits" = 16384;
          "strict sync" = "no";

          "load printers" = "no";
          printing = "bsd";
          "printcap name" = "/dev/null";
          "disable spoolss" = "yes";
          "show add printer wizard" = "no";

          # SMB プロトコルバージョン（iOS/macOS 互換性）
          "min protocol" = "SMB2";
          "max protocol" = "SMB3_11";

          # VFS モジュール（Apple デバイス互換性に必須）
          "vfs objects" = "acl_xattr catia fruit streams_xattr";

          # Fruit モジュール設定（iOS/macOS 最適化）
          "fruit:metadata" = "stream";
          "fruit:model" = "MacSamba";
          "fruit:posix_rename" = "yes";
          "fruit:veto_appledouble" = "no";
          "fruit:nfs_aces" = "no";
          "fruit:wipe_intentionally_left_blank_rfork" = "yes";
          "fruit:delete_empty_adfiles" = "yes";

          interfaces = "eth0";
          "bind interfaces only" = true;
          "guest account" = "nobody";
          "map to guest" = "bad user";

          "dos charset" = "CP932";
          "unix charset" = "UTF-8";
        };
        tanabe-media = {
          path = "/mnt/data/tanabe-media";
          browseable = "yes";
          available = "yes";
          public = "yes";
          writable = "yes";
          "read only" = "no";
          "guest ok" = "yes";
          "create mask" = "0644";
          "directory mask" = "0755";
          "force user" = "narinari";
          "force group" = "users";
        };
        xxx = {
          path = "/mnt/data/xxx";
          browseable = "no";
          available = "yes";
          writable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "create mask" = "0644";
          "directory mask" = "0755";
          "force user" = "narinari";
          "force group" = "users";
          "valid users" = "narinari";
        };
      };
    };

    # Avahi SMBサービス公開
    avahi.extraServiceFiles = {
      smb = ''
        <?xml version="1.0" standalone='no'?><!--*-nxml-*-->
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">%h</name>
          <service>
            <type>_smb._tcp</type>
            <port>445</port>
          </service>
        </service-group>
      '';
    };

    # Prometheus smartctl exporter（jarvis固有）
    prometheus.exporters.smartctl = {
      enable = true;
      openFirewall = true;
      devices = [
        "/dev/sda"
        "/dev/sdb"
        "/dev/sdc"
        "/dev/sdd"
      ];
    };

    # NFS Server
    nfs.server = {
      enable = true;
      exports = ''
        /export            192.168.100.0/24(rw,sync,no_subtree_check,crossmnt,fsid=0)
        /export/fx-trading 192.168.100.0/24(rw,sync,no_root_squash,no_subtree_check,nohide)
      '';
      createMountPoints = true;
    };
  };

  system.stateVersion = "23.11";
}
