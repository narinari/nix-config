{ lib, pkgs, config, inputs, ... }:

{
  nix = {
    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = [ "nix-command" "flakes" "repl-flake" ];
      # Deduplicate and optimize nix store
      auto-optimise-store = true;

      substituters = [ "https://cache.nixos.org/" ];
      trusted-public-keys =
        [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];

      trusted-users = [ "@admin" ];
    };

    # Add each flake input as a registry
    # To make nix3 commands consistent with the flake
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    # Map registries to channels
    # Very useful when using legacy commands
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}")
      config.nix.registry;

    # Enable experimental nix command and flakes
    # nix.package = pkgs.nixUnstable;

    extraOptions = lib.optionalString (pkgs.system == "aarch64-darwin") ''
      extra-platforms = aarch64-darwin
    '';
    #   extra-platforms = x86_64-darwin aarch64-darwin
    # '';
  };

  programs = {
    nix-index.enable = true;
    command-not-found.enable = false;
  };
}
