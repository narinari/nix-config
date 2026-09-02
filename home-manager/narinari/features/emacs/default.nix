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

  # GUI版
  # darwin: emacs-macport (Mitsuharu Yamamoto port, Mac 最適化済み — emacs-plus 用パッチは不要/不適合)
  # Linux:  emacs-unstable-pgtk (Pure GTK / Wayland)
  patchedEmacs = if stdenv.isDarwin then pkgs.emacs-macport else pkgs.emacs-unstable-pgtk;
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
        texliveMedium # 26.05+ で combined.* は deprecated
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
