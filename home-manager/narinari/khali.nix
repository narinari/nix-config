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
    ./features/essentials
    ./features/emacs
    ./features/cli
    ./features/llm
    ./features/llm/aperture.nix
    ./features/llm/codex.nix
    ./features/llm/claude-code-skills.nix
    ./features/bitwarden
    ./features/rclone
    ./features/desktop/common
    ./features/desktop/dark-theme.nix
    ./features/desktop/fcitx5.nix
    ./features/desktop/hyprlock.nix
    ./features/desktop/hypridle.nix
    ./features/desktop/hyprpanel.nix
    ./features/desktop/hyprland.nix
    ./features/desktop/menu.nix
    ./features/desktop/niri.nix
    ./features/desktop/noctalia.nix
    ./linux
  ];

  # 両 WM (Hyprland / niri) で共有するユーティリティ。
  home.packages = with pkgs; [
    wl-clipboard # Wayland クリップボード
  ];

  systemd.user.startServices = "sd-switch";
}
