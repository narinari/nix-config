{ pkgs, ... }:

{
  default = pkgs.mkShell {
    name = "nix-config";
    NIX_CONFIG = "extra-experimental-features = nix-command flakes repl-flake";
    nativeBuildInputs = with pkgs; [
      git
      home-manager

      # Nix
      cachix
      deploy-rs
      nix-build-uncached
      nixpkgs-fmt
      age
      rnix-lsp
      statix

      # Lua
      # stylua
      # (luajit.withPackages (p: with p; [ luacheck ]))
      # sumneko-lua-language-server

      # Shell
      shellcheck
      shfmt

      # GitHub Actions
      act
      actionlint
      python3Packages.pyflakes
      shellcheck

      # Misc
      jq
      pre-commit
      rage
      sops
      git
    ];

    # shellHook = ''
    #   ${checks.pre-commit-check.shellHook}
    # '';
  };
}
