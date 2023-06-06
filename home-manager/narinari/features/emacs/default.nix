{ pkgs, config, lib, ... }:
let
  inherit (pkgs) stdenv;
  inherit (lib) optional mkIf;
  doom = {
    repoUrl = "https://github.com/doomemacs/doomemacs";
    configRepoUrl = "git@github.com.private:narinari/doom.git";
  };
  customEmacs =
    (pkgs.emacsPackagesFor pkgs.emacs-unstable-pgtk).emacsWithPackages
    (epkgs: [ epkgs.vterm ]);
in {
  home = {
    packages = with pkgs; [
      ## Emacs itself
      binutils # native-comp needs 'as', provided by this

      ## Doom dependencies
      git
      (ripgrep.override { withPCRE2 = true; })
      gnutls # for TLS connectivity

      ## Optional dependencies
      fd # faster projectile indexing
      imagemagick # for image-dired
      (mkIf config.programs.gpg.enable pinentry_emacs) # in-emacs gnupg prompts
      zstd # for undo-fu-session/undo-tree compression

      ## Module dependencies
      # :checkers spell
      (aspellWithDicts (ds: with ds; [ en en-computers en-science ]))
      # :tools editorconfig
      editorconfig-core-c # per-project style config
      # :tools lookup & :lang org +roam
      sqlite
      # :lang latex & :lang org (latex previews)
      texlive.combined.scheme-medium
      # unstable.fava # HACK Momentarily broken on nixos-unstable
    ];

    sessionPath = [ "${config.xdg.configHome}/emacs/bin" ];

    extraActivationPath = with pkgs; [ git openssh ];
    activation = {
      installDoomEmacs = ''
        if [ ! -d "${config.xdg.configHome}/emacs" ]; then
           $DRY_RUN_CMD git clone --depth=1 --single-branch "${doom.repoUrl}" "${config.xdg.configHome}/emacs"
           $DRY_RUN_CMD git clone "${doom.configRepoUrl}" "${config.xdg.configHome}/doom"
        fi
      '';
    };
  };

  programs.emacs = {
    enable = true;
    package = customEmacs.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ optional stdenv.isDarwin [
        # Fix OS window role (needed for window managers like yabai)
        (pkgs.fetchpatch {
          url =
            "https://raw.githubusercontent.com/d12frosted/homebrew-emacs-plus/master/patches/emacs-29/fix-window-role.patch";
          sha256 = "+z/KfsBm1lvZTZNiMbxzXQGRTjkCFO4QPlEK35upjsE=";
        })
        # Use poll instead of select to get file descriptors
        (pkgs.fetchpatch {
          url =
            "https://raw.githubusercontent.com/d12frosted/homebrew-emacs-plus/master/patches/emacs-29/poll.patch";
          sha256 = "jN9MlD8/ZrnLuP2/HUXXEVVd6A+aRZNYFdZF8ReJGfY=";
        })
        # Enable rounded window with no decoration
        (pkgs.fetchpatch {
          url =
            "https://raw.githubusercontent.com/d12frosted/homebrew-emacs-plus/master/patches/emacs-29/round-undecorated-frame.patch";
          sha256 = "sha256-uYIxNTyfbprx5mCqMNFVrBcLeo+8e21qmBE3lpcnd+4=";
        })
        # Make Emacs aware of OS-level light/dark mode
        (pkgs.fetchpatch {
          url =
            "https://raw.githubusercontent.com/d12frosted/homebrew-emacs-plus/master/patches/emacs-29/system-appearance.patch";
          sha256 = "oM6fXdXCWVcBnNrzXmF0ZMdp8j0pzkLE66WteeCutv8=";
        })
      ];
    });
  };
}
