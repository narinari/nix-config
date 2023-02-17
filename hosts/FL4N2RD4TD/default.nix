{ pkgs, lib, ... }:
{
  # Nix configuration ------------------------------------------------------------------------------
  nix = {
    settings = {
      substituters= [
        "https://cache.nixos.org/"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      ];

      trusted-users = [
        "@admin"
      ];
    };

    configureBuildUsers = true;

    # Enable experimental nix command and flakes
    # nix.package = pkgs.nixUnstable;
    extraOptions = ''
      auto-optimise-store = true
      experimental-features = nix-command flakes
    '' + lib.optionalString (pkgs.system == "aarch64-darwin") ''
      extra-platforms = x86_64-darwin aarch64-darwin
    '';
  };

  # Make sure the nix daemon always runs
  services.nix-daemon.enable = true;

  # Installs a version of nix, that dosen't need "experimental-features = nix-command flakes" in /etc/nix/nix.conf
  #services.nix-daemon.package = pkgs.nixFlakes;
  
  # if you use zsh (the default on new macOS installations),
  # you'll need to enable this so nix-darwin creates a zshrc sourcing needed environment changes
  programs.zsh.enable = true;
  # bash is enabled by default

  # Apps
  # `home-manager` currently has issues adding them to `~/Applications`
  # Issue: https://github.com/nix-community/home-manager/issues/1341
  environment.systemPackages = with pkgs; [
    kitty
    terminal-notifier
  ];

  programs.nix-index.enable = true;

  # Fonts
  fonts.fontDir.enable = true;
  fonts.fonts = with pkgs; [
    recursive
    (nerdfonts.override { fonts = [ "SpaceMono" ]; })
  ];

  # Keyboard
  system.keyboard.enableKeyMapping = true;
  system.keyboard.remapCapsLockToEscape = true;

  # Add ability to used TouchID for sudo authentication
  # security.pam.enableSudoTouchIdAuth = true;

  homebrew = {
    onActivation = {
      enable = true;
      autoUpdate = true;
    };

    casks = [
      "keycastr"
      "the-unarchiver"
      "aquaskk"
      "xquartz"
      "bestres"
      "google-chrome"
      "licecap"
      "contexts"
      "iterm2"
      "raycast"
      "firefox"
      "karabiner-elements"
      "skitch"
    ];
  };

  system.defaults.dock = {
    autohide = true;
    orientation = "right";
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    verbose = true;
  };
  home-manager.users.narinari = { pkgs, ... }: {
    home.stateVersion = "22.11";
  
    programs = {
      exa = {
        enable = true;
        enableAliases = true;
      };
      jq.enable = true;
      tmux = {
        enable = true;
        keyMode = "vi";
        clock24 = true;
        historyLimit = 10000;
        plugins = with pkgs.tmuxPlugins; [
          vim-tmux-navigator
          gruvbox
        ];
        extraConfig = ''
          new-session -s main
          bind-key -n C-a send-prefix
        '';
      };

      emacs = {
        enable = true;
        package = pkgs.emacsPgtk.overrideAttrs (old: {
          patches = (old.patches or []) ++ [
            # Fix OS window role (needed for window managers like yabai)
            (pkgs.fetchpatch {
              url = "https://raw.githubusercontent.com/d12frosted/homebrew-emacs-plus/master/patches/emacs-28/fix-window-role.patch";
              sha256 = "+z/KfsBm1lvZTZNiMbxzXQGRTjkCFO4QPlEK35upjsE=";
            })
            # Use poll instead of select to get file descriptors
            (pkgs.fetchpatch {
              url = "https://raw.githubusercontent.com/d12frosted/homebrew-emacs-plus/master/patches/emacs-29/poll.patch";
              sha256 = "jN9MlD8/ZrnLuP2/HUXXEVVd6A+aRZNYFdZF8ReJGfY=";
            })
            # Enable rounded window with no decoration
            (pkgs.fetchpatch {
              url = "https://raw.githubusercontent.com/d12frosted/homebrew-emacs-plus/master/patches/emacs-29/round-undecorated-frame.patch";
              sha256 = "qPenMhtRGtL9a0BvGnPF4G1+2AJ1Qylgn/lUM8J2CVI=";
            })
            # Make Emacs aware of OS-level light/dark mode
            (pkgs.fetchpatch {
              url = "https://raw.githubusercontent.com/d12frosted/homebrew-emacs-plus/master/patches/emacs-28/system-appearance.patch";
              sha256 = "oM6fXdXCWVcBnNrzXmF0ZMdp8j0pzkLE66WteeCutv8=";
            })
          ];
        });
      };
    };
  };
}
