{ pkgs, checks, ... }:

system:

with pkgs;

mkShell {
  name = "nix-config";

  nativeBuildInputs = [
    # Nix
    cachix
    deploy-rs
    nix-build-uncached
    nixpkgs-fmt
    agenix
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

  shellHook = ''
    ${checks.pre-commit-check.shellHook}
  '';
}
