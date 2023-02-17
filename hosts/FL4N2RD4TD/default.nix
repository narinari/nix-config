{ pkgs, ... }:
{
  # Make sure the nix daemon always runs
  services.nix-daemon.enable = true;
  # Installs a version of nix, that dosen't need "experimental-features = nix-command flakes" in /etc/nix/nix.conf
  #services.nix-daemon.package = pkgs.nixFlakes;
  
  # if you use zsh (the default on new macOS installations),
  # you'll need to enable this so nix-darwin creates a zshrc sourcing needed environment changes
  programs.zsh.enable = true;
  # bash is enabled by default

  homebrew = {
    onActivation = {
      enable = true;
      autoUpdate = true;
    };

    casks = [
      "alacritty"
      "font-space-mono-nerd-font"
      "keycastr"
      "the-unarchiver"
      "aquaskk"
      "franz"
      "kitty"
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
