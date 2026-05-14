{
  pkgs,
  self,
  pre-commit-hooks,
  deploy-rs,
  ...
}:

system:

with pkgs;

{
  pre-commit-check = pre-commit-hooks.lib.${system}.run {
    src = lib.cleanSource ../.;
    hooks = {
      actionlint.enable = true;
      # luacheck.enable = true;
      nixfmt-rfc-style = {
        enable = true;
        excludes = [ "hardware-configuration.*.nix" ];
      };
      shellcheck.enable = true;
      shfmt = {
        enable = true;
        excludes = [
          "home-manager/narinari/work/work-config/aws.zsh"
        ];
      };
      statix = {
        enable = true;
        # NOTE: settings.ignore は pre-commit-hooks.nix が複数要素を 1 つの
        # `--ignore` 引数に空白連結してしまい、2 つ目以降が positional path
        # 扱いになって逆効果。ignore は repo 直下の statix.toml に集約する。
      };
      # stylua.enable = true;
      git-secrets = {
        enable = true;
        name = "Git Secrets";
        description = "git-secrets scans commits, commit messages, and --no-ff merges to prevent adding secrets into your git repositories.";
        entry = "${git-secrets}/bin/git-secrets --pre_commit_hook";
        language = "script";
        excludes = [ "hardware-configuration.*.nix" ];
      };
    };

  };
}
// (deploy-rs.lib.${system}.deployChecks self.deploy)
