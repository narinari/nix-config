{ pkgs, config, inputs, outputs, ... }:

{
  imports = [ ./git.nix ./zsh.nix ];

  sops.secrets.work-env = {
    sopsFile = "${inputs.my-secrets}/work/c-fo.yaml";
    path = "${config.xdg.dataHome}/profile/work-env.sh";
  };

  home.packages = [ outputs.packages.${pkgs.system}.fosi ];

  programs = {
    ssh = {
      enable = true;
      includes = [ "${./ssh/work/config}" ];
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
