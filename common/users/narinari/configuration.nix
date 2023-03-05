{ config, lib, pkgs, ... }:

{
  # Secrets
  age = {
    identityPaths = [
      "/Users/narinari/.ssh/id_ed25519"
      "/Users/narinari/.ssh/narinari.t/id_ed25519"
    ];
  };

  users.users.narinari = {
    name = "narinari";
    shell = lib.mkIf config.programs.zsh.enable pkgs.zsh;
  } // lib.optionalAttrs pkgs.stdenv.isDarwin {
    home =
      "/Users/narinari"; # need only on macos https://github.com/LnL7/nix-darwin/issues/423
  } // lib.optionalAttrs pkgs.stdenv.isLinux {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = (../../../keys/secrets.nix).allKeys;
  };

}
