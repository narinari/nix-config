{ pkgs, pre-commit-hooks, ... }:

system:

with pkgs;

{
  pre-commit-check = pre-commit-hooks.lib.${system}.run {
    src = lib.cleanSource ../.;
    hooks = {
      actionlint.enable = true;
      # luacheck.enable = true;
      nixfmt = {
        enable = true;
        excludes = [ "hardware-configuration.*.nix" ];
      };
      shellcheck.enable = true;
      shfmt = {
        enable = true;
        excludes = [ "hosts/FL4N2RD4TD/core/p10k-config/p10k.zsh" ];
      };
      statix.enable = true;
      # stylua.enable = true;
      git-secrets = {
        enable = true;
        name = "Git Secrets";
        description =
          "git-secrets scans commits, commit messages, and --no-ff merges to prevent adding secrets into your git repositories.";
        entry = "${git-secrets}/bin/git-secrets --pre_commit_hook";
        language = "script";
      };
    };
  };
} # // (deploy-rs.lib.${system}.deployChecks self.deploy)
