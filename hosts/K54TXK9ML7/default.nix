{ pkgs, inputs, ... }:

{
  imports = [
    ../common/global
    ../common/darwin
    ../common/users/narinari
  ];

  networking = {
    hostName = "K54TXK9ML7";
  };

  system.stateVersion = 4;

  system.primaryUser = "narinari";

  # Add ability to used TouchID for sudo authentication
  security.pam.services.sudo_local.touchIdAuth = true;
}
