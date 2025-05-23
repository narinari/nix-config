{
  inputs,
  lib,
  pkgs,
  config,
  outputs,
  ...
}:

let
  emacs-pkg = config.programs.emacs.package;
  org-journal-new-entry = pkgs.writeShellScript "org-journal-new-entry" ''
    # for Raycast
    # Required parameters:
    # @raycast.schemaVersion 1
    # @raycast.title Add new entry of org-journal
    # @raycast.mode silent

    EMACS_CLINET=${emacs-pkg}/bin/emacsclient
    if $EMACS_CLINET -n -e "(select-frame-set-input-focus (selected-frame))" >/dev/null 2>&1; then
    	$EMACS_CLINET -n -e "(org-journal-new-entry nil)" >/dev/null
    else
    	$EMACS &
    	$EMACS_CLINET -n -e "(org-journal-new-entry nil)" >/dev/null
    fi
  '';
in
{
  imports = [
    ../features/essentials
    ../features/emacs
  ];

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
      experimental-features = [
        "nix-command"
        "flakes"
      ];
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
    file.".local/bin/org-journal-new-entry".source = org-journal-new-entry;
  };

  xdg.enable = true;
}
