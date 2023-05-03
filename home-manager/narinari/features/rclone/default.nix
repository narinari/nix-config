{ config, lib, pkgs, inputs, ... }:
let
  mkSyncScript = name:
    pkgs.writeShellScript "${name}.sh" ''
      set -euo pipefail
      ${pkgs.rclone}/bin/rclone sync $HOME/GoogleDrive/org p_drive:org
    '';
in {
  sops.secrets."rclone.conf" = {
    sopsFile = "${inputs.my-secrets}/private/rclone.yaml";
    path = "${config.xdg.configHome}/rclone/rclone.conf";
  };

  home.packages = with pkgs; [ rclone ];

  systemd.user.services."rclone-sync" = {
    Unit.Description = "Sync files to cloud";

    Service = {
      Type = "oneshot";
      ExecStart = "${mkSyncScript "rclone-sync"}";
    };

    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.timers."rclone-sync" = {
    Unit.Description = "Perform an rclone sync periodically.";

    Timer = {
      OnCalendar = "*:0/10";
      OnBootSec = "3min";
      OnUnitActiveSec = "5min";
    };

    Install.WantedBy = [ "timers.target" ];
  };
}
