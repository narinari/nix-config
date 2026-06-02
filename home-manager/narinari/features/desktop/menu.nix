{ pkgs, lib, ... }:

let
  # wlr-which-key を使ったポップアップメニューを実行可能スクリプトとして生成する。
  # 生成されるバイナリは Wayland compositor 非依存 (layer-shell) で、
  # Hyprland / niri どちらのセッションからも `name` で起動できる。
  mkMenu =
    name: menu:
    let
      configFile = pkgs.writeText "${name}.yaml" (
        lib.generators.toYAML { } {
          anchor = "bottom-right";
          inherit menu;
        }
      );
    in
    pkgs.writeShellScriptBin name ''
      exec ${lib.getExe pkgs.wlr-which-key} ${configFile}
    '';

  browserMenu = [
    {
      key = "f";
      desc = "Firefox";
      cmd = "/etc/profiles/per-user/narinari/bin/firefox";
    }
    {
      key = "c";
      desc = "Chrome";
      cmd = "/etc/profiles/per-user/narinari/bin/google-chrome";
    }
  ];

  emacsMenu = [
    {
      key = "e";
      desc = "Emacs";
      cmd = "emacs";
    }
    {
      key = "d";
      desc = "Emacs dired";
      cmd = "emacs";
    }
  ];
in
{
  home.packages = [
    (mkMenu "menu-browser" browserMenu)
    (mkMenu "menu-emacs" emacsMenu)
  ];
}
