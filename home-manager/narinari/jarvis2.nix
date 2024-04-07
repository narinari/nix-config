{ inputs, outputs, consig, pkgs, ... }:

{
  imports = [ ./global ./features/terminal-access ];

  targets.genericLinux.enable = true;

  # linux only
  services = {
    syncthing.enable = true;
    easyeffects.enable = true;
    systembus-notify.enable = true;
  };

  systemd.user.startServices = "sd-switch";
}
