{ inputs, lib, pkgs, config, outputs, ... }:

{
  imports = [ ../features/cli ../features/emacs ];

  nixpkgs = {
    overlays = builtins.attrValues outputs.overlays;
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
      permittedInsecurePackages = [ "openssl-1.1.1u" ];
    };
  };

  nix = {
    package = lib.mkDefault pkgs.nix;
    settings = {
      experimental-features = [ "nix-command" "flakes" "repl-flake" ];
      warn-dirty = false;
    };
  };

  # systemd.user.startServices = "sd-switch";

  programs = {
    home-manager.enable = true;
    git.enable = true;
  };

  sops = {
    age.keyFile = "${config.xdg.configHome}/sops/age/keys.txt";
    defaultSopsFile = ./secrets.yaml;
  };

  home = {
    username = lib.mkDefault "narinari";
    homeDirectory = lib.mkDefault "/home/${config.home.username}";
    stateVersion = lib.mkDefault "23.05";

    language.base = "ja_JP.UTF-8";

    sessionPath = [ "$HOME/.local/bin" ];
    sessionVariables = {
      SOPS_AGE_KEY_FILE = config.sops.age.keyFile; # for macos
    };

    file.".local/bin" = {
      source = ./home/bin;
      recursive = true;
      executable = true;
    };
  };
}
