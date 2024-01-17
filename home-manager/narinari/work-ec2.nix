{ inputs, outputs, consig, pkgs, ... }:

{
  imports = [ ./global ./work ./features/terminal-access ];

  targets.genericLinux.enable = true;

  # linux only
  services = {
    syncthing.enable = false;
    easyeffects.enable = true;
    systembus-notify.enable = true;
  };

  systemd.user.startServices = "sd-switch";
}
