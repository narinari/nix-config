{ pkgs, checks, ... }:

{
  default = pkgs.mkShell {
    name = "nix-config";
    NIX_CONFIG = "extra-experimental-features = nix-command flakes";
    nativeBuildInputs = with pkgs; [
      nix
      git
      home-manager

      # Nix
      cachix
      deploy-rs
      nix-build-uncached
      nixpkgs-fmt
      sops
      # age
      rage
      ssh-to-age
      nil
      statix

      # Shell
      shellcheck
      shfmt

      # GitHub Actions
      act
      actionlint
      python3Packages.pyflakes

      # Misc
      jq
      pre-commit
    ];

    shellHook = ''
      ${checks.pre-commit-check.shellHook}
    '';
  };
}
