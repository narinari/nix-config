{
  inputs,
  outputs,
  config,
  pkgs,
  ...
}:

{
  imports = [
    ./global
    ./features/terminal-access
  ];

  targets.genericLinux.enable = true;

  services = {
    syncthing.enable = true;
    systembus-notify.enable = true;
  };

  systemd.user.startServices = "sd-switch";
}
