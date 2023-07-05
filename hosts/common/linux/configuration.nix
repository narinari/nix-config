{ pkgs, ... }:

{
  imports = [ ./nix-optimizations.nix ];

  nix = {
    # TODO: temporary fix for NixOS/nix#7704
    package = pkgs.nixVersions.nix_2_12;
    gc = {
      automatic = true;
      dates = "weekly";
      # Delete older generations too
      options = "--delete-older-than 7d";
    };
  };

  targets.genericLinux.enable = true;
}
