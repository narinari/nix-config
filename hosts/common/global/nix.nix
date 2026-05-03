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
    distributedBuilds = true;

    buildMachines = [
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
        publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUo1YVU5SC9DRjhRdmZ6UGVDOUZpbkI1WEJiNXUxRk1VbzMrcjM2Z1JrMWwgcmluLWhvc3QK";
      }
      # jarvis RPi4 (aarch64-linux ビルド用)
      {
        hostName = "jarvis.local";
        system = "aarch64-linux";
        protocol = "ssh-ng";
        sshUser = "builder";
        sshKey = "/etc/nix/rin_builder_ed25519";
        maxJobs = 2;
        speedFactor = 1;
        supportedFeatures = [ "benchmark" ];
        publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUswVW9PcXRYRzdjMHZGTzBJR2tIYnV0RDR4cDlQYU9ISklvaldKbmxPUnUgamFydmlz";
      }
      # friday RPi4 (aarch64-linux ビルド用)
      {
        hostName = "friday.local";
        system = "aarch64-linux";
        protocol = "ssh-ng";
        sshUser = "builder";
        sshKey = "/etc/nix/rin_builder_ed25519";
        maxJobs = 2;
        speedFactor = 1;
        supportedFeatures = [ "benchmark" ];
        publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUdIczRGc0R6blplQ2Y0V0orV2hNNENEK3l2aVA4YVphcVgvZitibUhXYy8gZnJpZGF5";
      }
    ];

    extraOptions = ''
      extra-platforms = aarch64-linux aarch64-darwin i686-linux
      builders-use-substitutes = true
    '';
  };

  programs = {
    nix-index.enable = true;
  };
}
