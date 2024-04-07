{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    "${modulesPath}/installer/sd-card/sd-image-aarch64-new-kernel-no-zfs-installer.nix"
    ../common/global
    ../common/rpi4
    ../common/linux
    ../common/linux/home-network.nix
    ../common/users/narinari
  ];

  networking = { hostName = lib.mkDefault "rpi4-base"; };

  nixpkgs.hostPlatform = "aarch64-linux";
  system.stateVersion = "23.11";

  services.openssh.settings.PermitRootLogin = lib.mkImageMediaOverride "yes";

  # from profiles/minimal.nix
  # environment.noXlibs = true;
  documentation = {
    enable = false;
    doc.enable = false;
    info.enable = false;
    man.enable = false;
    nixos.enable = false;
  };
}
