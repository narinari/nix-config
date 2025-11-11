{
  config,
  lib,
  pkgs,
  outputs,
  baseHostname ? "",
  ...
}:

let
  ifTheyExist = groups: builtins.filter (group: builtins.hasAttr group config.users.groups) groups;
in
{
  users.users.narinari = {
    name = "narinari";
    shell = lib.mkIf config.programs.zsh.enable pkgs.zsh;
    packages = [ pkgs.home-manager ];
  }
  // lib.optionalAttrs pkgs.stdenv.isDarwin {
    home = "/Users/narinari"; # need only on macos https://github.com/LnL7/nix-darwin/issues/423
  }
  // lib.optionalAttrs pkgs.stdenv.isLinux {
    isNormalUser = true;
    # openssh.authorizedKeys.keys = (../../../keys/secrets.nix).allKeys;
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../../../../home-manager/narinari/id_ed25519.pub)
    ];
    extraGroups = [
      "wheel"
      "video"
      "audio"
    ]
    ++ ifTheyExist [
      "network"
      # "wireshark"
      "i2c"
      "mysql"
      "docker"
      "podman"
      "git"
      "libvirtd"
      "deluge"
    ];
  };

  home-manager.users.narinari = import ../../../../home-manager/narinari/${
    if baseHostname == "" then config.networking.hostName else baseHostname
  }.nix;
}
