{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:

{
  nix = {
    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      substituters = [
        "https://cache.nixos.org/"
        "https://nix-community.cachix.org/"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];

      trusted-users = [
        "@wheel"
        "@admin"
        "narinari"
      ];
    };

    # Deduplicate and optimize nix store
    optimise.automatic = true;

    # Add each flake input as a registry
    # To make nix3 commands consistent with the flake
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    # Map registries to channels
    # Very useful when using legacy commands
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

    # Enable experimental nix command and flakes
    # nix.package = pkgs.nixUnstable;

    # macOS のみリモートビルダーを有効化
    distributedBuilds = lib.mkIf (pkgs.system == "aarch64-darwin") true;

    buildMachines = lib.optionals (pkgs.system == "aarch64-darwin") [
      # macOS 付属の Linux VM (aarch64-linux クロスコンパイル用)
      {
        hostName = "linux-builder";
        system = "aarch64-linux";
        protocol = "ssh-ng";
        sshUser = "builder";
        sshKey = "/etc/nix/builder_ed25519";
        maxJobs = 4;
        supportedFeatures = [
          "kvm"
          "benchmark"
          "big-parallel"
        ];
        publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUpCV2N4Yi9CbGFxdDFhdU90RStGOFFVV3JVb3RpQzVxQkorVXVFV2RWQ2Igcm9vdEBuaXhvcwo=";
      }
      # rin LXC (x86_64-linux ビルド用)
      {
        hostName = "rin.local";
        system = "x86_64-linux";
        protocol = "ssh-ng";
        sshUser = "builder";
        sshKey = "/etc/nix/rin_builder_ed25519";
        maxJobs = 4;
        speedFactor = 2;
        supportedFeatures = [
          "benchmark"
          "big-parallel"
        ];
        publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSU5LbUp6VHJ0UWNNOVVoT2NjV1pGbVRVQjFkTkRQekVuYjlZN2dNMW93V0sgbmFyaW5hcmlAa2hhbGk=";
      }
    ];

    extraOptions = lib.optionalString (pkgs.system == "aarch64-darwin") ''
      extra-platforms = aarch64-darwin
      builders-use-substitutes = true
    '';
  };

  programs = {
    nix-index.enable = true;
  };
}
