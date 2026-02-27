{
  inputs,
  outputs,
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./global
    ./features/cli
    ./features/llm
    ./features/terminal-access
  ];

  targets.genericLinux.enable = true;

  # ターミナル版Emacsを有効化（LXCでGUI不要）
  programs.emacs.terminal = true;

  services = {
    syncthing.enable = true;
    systembus-notify.enable = true;
  };

  systemd.user.startServices = "sd-switch";
}
