{ pkgs, inputs, ... }:

{
  imports = [
    ../common/global
    ../common/darwin
    ../common/users/narinari
  ];

  networking = {
    hostName = "FL4N2RD4TD";
  };

  system.stateVersion = 4;

  # Add ability to used TouchID for sudo authentication
  security.pam.services.sudo_local.touchIdAuth = true;
}
