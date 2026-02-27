{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (pkgs) stdenv;
  inherit (lib) optional mkIf;

  doom = {
    repoUrl = "https://github.com/doomemacs/doomemacs";
    configRepoUrl = "git@github.com.private:narinari/doom.git";
  };

  # 共通のtree-sitter grammars（全ホストで共有）
  treesitterGrammars =
    epkgs: with epkgs; [
      (treesit-grammars.with-grammars (
        p: with p; [
          tree-sitter-bash
          tree-sitter-c
          tree-sitter-c-sharp
          tree-sitter-cmake
          tree-sitter-css
          tree-sitter-scss
          tree-sitter-dockerfile
          tree-sitter-elisp
          tree-sitter-go
          tree-sitter-gomod
          tree-sitter-haskell
          tree-sitter-html
          tree-sitter-javascript
          tree-sitter-json
          tree-sitter-make
          tree-sitter-markdown
          tree-sitter-markdown-inline
          tree-sitter-nix
          tree-sitter-python
          tree-sitter-ruby
          tree-sitter-rust
          tree-sitter-toml
          tree-sitter-tsx
          tree-sitter-typescript
          tree-sitter-yaml
        ]
      ))
    ];

  # 共通Emacsパッケージ
  commonEmacsPackages = epkgs: with epkgs; [ vterm ] ++ treesitterGrammars epkgs;

  # GUI版（Darwin向けパッチ付き）
  patchedEmacs = pkgs.emacs-unstable-pgtk.overrideAttrs (old: {
    patches =
      (old.patches or [ ])
      ++ optional stdenv.isDarwin [
        # Fix OS window role (needed for window managers like yabai)
        (pkgs.fetchpatch {
          url = "https://raw.githubusercontent.com/d12frosted/homebrew-emacs-plus/master/patches/emacs-28/fix-window-role.patch";
          sha256 = "+z/KfsBm1lvZTZNiMbxzXQGRTjkCFO4QPlEK35upjsE=";
        })
        # Enable rounded window with no decoration
        (pkgs.fetchpatch {
          url = "https://raw.githubusercontent.com/d12frosted/homebrew-emacs-plus/master/patches/emacs-30/round-undecorated-frame.patch";
          sha256 = "sha256-uYIxNTyfbprx5mCqMNFVrBcLeo+8e21qmBE3lpcnd+4=";
        })
        # Make Emacs aware of OS-level light/dark mode
        (pkgs.fetchpatch {
          url = "https://raw.githubusercontent.com/d12frosted/homebrew-emacs-plus/master/patches/emacs-30/system-appearance.patch";
          sha256 = "3QLq91AQ6E921/W9nfDjdOUWR8YVsqBAT/W9c1woqAw=";
        })
      ];
  });
  guiEmacs = (pkgs.emacsPackagesFor patchedEmacs).emacsWithPackages commonEmacsPackages;

  # ターミナル版（emacs-nox）
  terminalEmacs = (pkgs.emacsPackagesFor pkgs.emacs-nox).emacsWithPackages commonEmacsPackages;
in
{
  options.programs.emacs.terminal = lib.mkEnableOption "Use terminal-only Emacs (emacs-nox)";

  config = {
    home = {
      packages = with pkgs; [
        ## Emacs itself
        binutils # native-comp needs 'as', provided by this

        ## Doom dependencies
        git
        (ripgrep.override { withPCRE2 = true; })
        gnutls # for TLS connectivity
        cmake

        ## Optional dependencies
        fd # faster projectile indexing
        imagemagick # for image-dired
        (mkIf config.programs.gpg.enable pinentry-emacs) # in-emacs gnupg prompts
        zstd # for undo-fu-session/undo-tree compression

        ## Module dependencies
        # :checkers spell
        (aspellWithDicts (
          ds: with ds; [
            en
            en-computers
            en-science
          ]
        ))
        # :tools editorconfig
        editorconfig-core-c # per-project style config
        # :tools lookup & :lang org +roam
        sqlite
        # :lang latex & :lang org (latex previews)
        texlive.combined.scheme-medium
        # unstable.fava # HACK Momentarily broken on nixos-unstable
      ];

      sessionPath = [ "${config.xdg.configHome}/emacs/bin" ];

      # Doom環境変数
      sessionVariables = {
        EMACSDIR = "${config.xdg.configHome}/emacs";
        DOOMDIR = "${config.xdg.configHome}/doom";
        DOOMLOCALDIR = "${config.xdg.dataHome}/doom";
      };

      extraActivationPath = with pkgs; [
        git
        openssh
      ];
      # activation = {
      #   installDoomEmacs = ''
      #     if [ ! -d "${config.xdg.configHome}/emacs" ]; then
      #        $DRY_RUN_CMD git clone --depth=1 --single-branch "${doom.repoUrl}" "${config.xdg.configHome}/emacs"
      #        $DRY_RUN_CMD git clone "${doom.configRepoUrl}" "${config.xdg.configHome}/doom"
      #     fi
      #   '';
      # };
    };

    programs.emacs = {
      enable = true;
      package = if config.programs.emacs.terminal then terminalEmacs else guiEmacs;
    };
  };
}
