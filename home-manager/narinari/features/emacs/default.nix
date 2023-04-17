{ pkgs, config, lib, ... }:
let
  inherit (pkgs) stdenv;
  inherit (lib) optional;
in {
  programs.emacs = {
    enable = true;
    package = pkgs.emacsUnstablePgtk.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ optional stdenv.isDarwin [
        # Fix OS window role (needed for window managers like yabai)
        (pkgs.fetchpatch {
          url =
            "https://raw.githubusercontent.com/d12frosted/homebrew-emacs-plus/master/patches/emacs-28/fix-window-role.patch";
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
          sha256 = "qPenMhtRGtL9a0BvGnPF4G1+2AJ1Qylgn/lUM8J2CVI=";
        })
        # Make Emacs aware of OS-level light/dark mode
        (pkgs.fetchpatch {
          url =
            "https://raw.githubusercontent.com/d12frosted/homebrew-emacs-plus/master/patches/emacs-28/system-appearance.patch";
          sha256 = "oM6fXdXCWVcBnNrzXmF0ZMdp8j0pzkLE66WteeCutv8=";
        })
      ];
    });
  };
}
