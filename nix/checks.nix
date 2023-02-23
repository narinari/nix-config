{ self, pre-commit-hooks, deploy-rs, ... }:

system:

with self.pkgs.${system};

{
  pre-commit-check = pre-commit-hooks.lib.${system}.run {
    src = lib.cleanSource ../.;
    hooks = {
      actionlint.enable = true;
      # luacheck.enable = true;
      nixpkgs-fmt = {
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
    };
  };
} // (deploy-rs.lib.${system}.deployChecks self.deploy)
