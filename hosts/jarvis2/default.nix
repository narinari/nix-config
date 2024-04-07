{ config, lib, pkgs, modulesPath, inputs, ... }:

{
  imports = [ ../rpi4-base ];

  networking = { hostName = "jarvis2"; };

  system.stateVersion = "23.11";

}
