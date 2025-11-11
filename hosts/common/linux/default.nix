{ pkgs, inputs, ... }:

{
  imports = [
    inputs.home-manager.nixosModules.home-manager
    ./locale.nix
    ./nix-optimizations.nix
    ./openssh.nix
    ./sops.nix
  ];

  #nix = {
  #  # TODO: temporary fix for NixOS/nix#7704
  #  package = pkgs.nixVersions.nix_2_12;
  #};

  environment = {
    enableAllTerminfo = true;
    shells = with pkgs; [
      zsh
      bashInteractive
    ];
  };

  hardware.enableRedistributableFirmware = true;

  # Increase open file limit for sudoers
  security.pam.loginLimits = [
    {
      domain = "@wheel";
      item = "nofile";
      type = "soft";
      value = "524288";
    }
    {
      domain = "@wheel";
      item = "nofile";
      type = "hard";
      value = "1048576";
    }
  ];

  # targets.genericLinux.enable = true;
  services.avahi = {
    enable = true;
    nssmdns = true;
    publish = {
      enable = true;
      userServices = true;
      addresses = true;
    };
  };
}
