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

    # 対話 shell から `hermes` CLI を起動したときに browser_navigate が動くよう、
    # tools/browser_tool.py::_find_agent_browser() が PATH で agent-browser を
    # 発見できるようにする。これが無いと npx フォールバックが走り、generic Linux 向けの
    # dynamic-linked バイナリが NixOS で起動できず "Could not start dynamically
    # linked executable" で失敗する。systemd service 経路は
    # hosts/khali/hermes-agent.nix の extraPackages 側で既に解決済み。
    agent-browser
    chromium
  ];

  # agent-browser が spawn する Chromium を Playwright DL ではなく Nix store の
  # chromium に固定する。systemd service 側は hosts/khali/hermes-agent.nix の
  # hermesEnvFile (AGENT_BROWSER_EXECUTABLE_PATH) で同等の値をセット済み。
  home.sessionVariables = {
    AGENT_BROWSER_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
  };

  systemd.user.startServices = "sd-switch";
}
