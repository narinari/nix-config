{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    inputs.nixos-generators.nixosModules.all-formats
    ../common/global
    ../common/linux
    ../common/users/narinari
  ];

  networking = { hostName = "rin"; };

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "23.05";

  formatConfigs.proxmox = { config, ... }: {
    proxmox.qemuConf = {
      name = "nixos-${config.system.nixos.label}-rin";
      cores = 2;
      memory = 4096;
    };
  };

  # customize an existing format
  formatConfigs.vmware = { config, ... }: { services.openssh.enable = true; };

  # define a new format
  formatConfigs.my-custom-format = { config, modulesPath, ... }: {
    imports =
      [ "${toString modulesPath}/installer/cd-dvd/installation-cd-base.nix" ];
    formatAttr = "isoImage";
    fileExtension = ".iso";
    networking.wireless.networks = {
      # ...
    };
  };
}
