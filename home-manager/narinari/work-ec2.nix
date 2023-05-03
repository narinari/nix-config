{ inputs, outputs, consig, pkgs, ... }:

{
  imports =
    [ inputs.sops-nix.homeManagerModule ./global ./work ./features/rclone ];

  # linux only
  # services = {
  #   syncthing.enable = true;
  #   easyeffects.enable = true;
  #   systembus-notify.enable = true;
  # };

  # systemd.user.startServices = "sd-switch";

}
