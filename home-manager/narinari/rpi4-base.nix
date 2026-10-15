{
  inputs,
  outputs,
  consig,
  pkgs,
  ...
}:

{
  imports = [
    ./global
    ./features/terminal-access
  ];

  targets.genericLinux.enable = true;

  # ヘッドレスサーバなのでターミナル版 Emacs (emacs-nox、バイナリキャッシュあり)。
  # GUI 版 emacs-unstable-pgtk は RPi4 上でのソースビルドに数時間かかる。
  programs.emacs.terminal = true;

  # linux only
  services = {
    syncthing.enable = true;
    easyeffects.enable = true;
    systembus-notify.enable = true;
  };

  systemd.user.startServices = "sd-switch";
}
