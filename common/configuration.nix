{ lib, pkgs, ... }:

{
  imports = [ ./home-manager.nix ./nix-flakes.nix ];

  environment.systemPackages = with pkgs; [ git terminal-notifier ];

  nix = {
    generateRegistryFromInputs = true;
    generateNixPathFromInputs = true;
    linkInputs = true;

    settings = {
      substituters = [ "https://cache.nixos.org/" ];
      trusted-public-keys =
        [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];

      trusted-users = [ "@admin" ];
    };

    configureBuildUsers = true;

    # Enable experimental nix command and flakes
    # nix.package = pkgs.nixUnstable;
    extraOptions = ''
      auto-optimise-store = true
      experimental-features = nix-command flakes
    '' + lib.optionalString (pkgs.system == "aarch64-darwin") ''
      extra-platforms = aarch64-darwin
    '';
    #   extra-platforms = x86_64-darwin aarch64-darwin
    # '';
  };

  programs = {
    zsh.enable = true;
    nix-index.enable = true;
  };
}
