{ inputs, outputs, consig, pkgs, ... }:

{
  imports = [
    inputs.sops-nix.homeManagerModule
    ./global
    ./work
    ./features/terminal-access
    ./features/rclone
  ];

  targets.genericLinux.enable = true;

  # linux only
  # services = {
  #   syncthing.enable = true;
  #   easyeffects.enable = true;
  #   systembus-notify.enable = true;
  # };

  # systemd.user.startServices = "sd-switch";

}
