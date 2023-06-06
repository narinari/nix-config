{ config, lib, pkgs, outputs, ... }:

let
  ifTheyExist = groups:
    builtins.filter (group: builtins.hasAttr group config.users.groups) groups;
in {
  users.users.narinari = {
    name = "narinari";
    shell = lib.mkIf config.programs.zsh.enable pkgs.zsh;
    packages = [ pkgs.home-manager ];
  } // lib.optionalAttrs pkgs.stdenv.isDarwin {
    home =
      "/Users/narinari"; # need only on macos https://github.com/LnL7/nix-darwin/issues/423
  } // lib.optionalAttrs pkgs.stdenv.isLinux {
    isNormalUser = true;
    openssh.authorizedKeys.keys = (../../../keys/secrets.nix).allKeys;
    extraGroups = [ "wheel" "video" "audio" ] ++ ifTheyExist [
      "network"
      "wireshark"
      "i2c"
      "mysql"
      "docker"
      "podman"
      "git"
      "libvirtd"
      "deluge"
    ];
  };

  home-manager.users.narinari =
    import ../../../../home-manager/narinari/${config.networking.hostName}.nix;
}
