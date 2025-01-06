{ pkgs, config, inputs, outputs, ... }:

{
  imports = [ ./git.nix ./zsh.nix ];

  sops.secrets = {
    work-env = {
      sopsFile = "${inputs.my-secrets}/work/c-fo.yaml";
      path = "${config.xdg.dataHome}/profile/work-env.sh";
    };
    work-git-config = {
      sopsFile = "${inputs.my-secrets}/work/c-fo.yaml";
      key = "git-config";
    };
  };

  home.packages = with outputs.packages.${pkgs.system}; [
    lsec2
    fosi
    pkgs.ssm-session-manager-plugin
  ];

  programs = {
    ssh = {
      enable = true;
      includes = [ config.sops.secrets.work-git-config.path ];
      matchBlocks = {
        "github.com.private" = {
          hostname = "github.com";
          user = "git";
          port = 22;
          identityFile = "~/.ssh/narinari.t/id_ed25519";
          identitiesOnly = true;

          extraOptions = { TCPKeepAlive = "yes"; };
        };

        "github.com" = {
          user = "git";
          identitiesOnly = true;

          extraOptions = { TCPKeepAlive = "yes"; };
        };
      };
    };
  };
}
