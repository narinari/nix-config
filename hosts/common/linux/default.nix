{ pkgs, ... }:

{
  imports = [ ./nix-optimizations.nix ];

  nix = {
    # TODO: temporary fix for NixOS/nix#7704
    package = pkgs.nixVersions.nix_2_12;
  };

  # targets.genericLinux.enable = true;
  services.avahi = {
    enable = true;
    nssmdns = true;
    publish.enable = true;
    publish.userServices = true;
    publish.addresses = true;
  };
}
