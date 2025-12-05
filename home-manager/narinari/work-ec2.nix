{
  inputs,
  outputs,
  consig,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./global
    ./features/cli
    ./features/llm
    inputs.my-private-modules.homeManagerModules.work
    ./features/terminal-access
  ];

  targets.genericLinux.enable = true;

  # linux only
  services = {
    syncthing.enable = false;
    easyeffects.enable = true;
    systembus-notify.enable = true;
  };

  systemd.user.startServices = "sd-switch";

  # for gpg-agent forwarding
  programs.gpg.settings = {
    no-autostart = true;
  };
  services.gpg-agent.enable = lib.mkForce false;

}
