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
    ./features/llm/plamo-translate.nix
    ./features/bitwarden
    ./features/rclone
    ./features/desktop/common
    ./features/desktop/dark-theme.nix
    ./features/desktop/fcitx5.nix
    ./features/desktop/hyprlock.nix
    ./features/desktop/hypridle.nix
    ./features/desktop/hyprland.nix
    ./features/desktop/menu.nix
    ./features/desktop/niri.nix
    ./features/desktop/noctalia.nix
    ./features/desktop/picard.nix
    ./linux
  ];

  # 両 WM (Hyprland / niri) で共有するユーティリティ。
  home.packages = with pkgs; [
    wl-clipboard # Wayland クリップボード

    vlc # メディアプレイヤー (VAAPI は hosts/khali/default.nix の hardware.graphics で有効)

    # hermes v0.23 以降は CLI も gateway (hermes-agent.service) に接続して動くため、
    # 対話 shell 用の agent-browser / AGENT_BROWSER_EXECUTABLE_PATH は不要になった。
    chromium
  ];

  systemd.user.startServices = "sd-switch";
}
