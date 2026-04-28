{ pkgs, inputs, ... }:

{
  imports = [
    ../common/global
    ../common/darwin
    ../common/users/narinari
  ];

  networking = {
    hostName = "hail-mary";
  };

  # Tailscale (GUI アプリ) + Codex CLI (OpenAI コーディングエージェント)
  homebrew.casks = [
    "tailscale"
    "codex"
  ];

  # jarvis の NFS 共有をマウント (launchd デーモン)
  # /Users/Shared/nas/fx-trading に起動時・ネットワーク変更時にマウント
  launchd.daemons.mount-nas = {
    script = ''
      MOUNT_POINT="/Users/Shared/nas/fx-trading"
      mkdir -p "$MOUNT_POINT"
      # 既にマウント済みならスキップ
      /sbin/mount | grep -q "$MOUNT_POINT" && exit 0
      # jarvis が見えるまで待つ (最大30秒)
      for i in $(seq 1 30); do
        /sbin/ping -c 1 -t 1 jarvis.local >/dev/null 2>&1 && break
        sleep 1
      done
      /sbin/mount_nfs -o nfsvers=3,resvport,soft,intr,rw \
        jarvis.local:/export/fx-trading "$MOUNT_POINT"
    '';
    serviceConfig = {
      RunAtLoad = true;
      StandardErrorPath = "/var/log/mount-nas.log";
      StandardOutPath = "/var/log/mount-nas.log";
      WatchPaths = [ "/var/run/resolv.conf" ]; # ネットワーク変更時に再実行
    };
  };

  # SmolVM 用ローカル OCI レジストリ (crane registry serve)
  # nix build した monitoring-ops イメージを SmolVM に配信するために常駐
  launchd.daemons.crane-registry = {
    script = ''
      ${pkgs.crane}/bin/crane registry serve --address=:1338
    '';
    serviceConfig = {
      RunAtLoad = true;
      KeepAlive = true;
      StandardErrorPath = "/var/log/crane-registry.log";
      StandardOutPath = "/var/log/crane-registry.log";
    };
  };

  # SmolVM 監視 ops 用: スリープ無効化
  power = {
    sleep = {
      computer = "never";
      display = 30;
      harddisk = "never";
    };
    restartAfterFreeze = true;
  };

  system = {
    # pmset で管理できない設定は activation script で
    activationScripts.postActivation.text = ''
      pmset -c powernap 0
      pmset -c tcpkeepalive 1
    '';
    defaults.SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false;
    stateVersion = 5;
    primaryUser = "narinari";
  };

  # Add ability to used TouchID for sudo authentication
  security.pam.services.sudo_local.touchIdAuth = true;
}
