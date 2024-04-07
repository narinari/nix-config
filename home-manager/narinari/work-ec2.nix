{ inputs, outputs, consig, pkgs, ... }:

{
  imports = [ ./global ./features/cli ./work ./features/terminal-access ];

  targets.genericLinux.enable = true;

  # linux only
  services = {
    syncthing.enable = false;
    easyeffects.enable = true;
    systembus-notify.enable = true;
  };

  systemd.user.startServices = "sd-switch";
}
