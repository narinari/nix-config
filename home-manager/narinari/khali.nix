{
  inputs,
  outputs,
  config,
  pkgs,
  lib,
  ...
}:

let
  mkMenu =
    menu:
    let
      configFile = pkgs.writeText "config.yaml" (
        lib.generators.toYAML { } {
          anchor = "bottom-right";
          # ...
          inherit menu;
        }
      );
    in
    pkgs.writeShellScriptBin "my-menu" ''
      exec ${lib.getExe pkgs.wlr-which-key} ${configFile}
    '';

  # 右上ホットコーナー: カーソルが右上隅に0.5秒滞在したらロック
  hotCornerScript = pkgs.writeShellScript "hypr-hot-corner" ''
    THRESHOLD=5
    DWELL_MS=500
    POLL=0.3
    in_corner=0
    corner_start=0
    while true; do
      pos=$(hyprctl cursorpos 2>/dev/null)
      [ -z "$pos" ] && sleep "$POLL" && continue
      x=''${pos%%,*}
      y=''${pos##*, }
      mon=$(hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[0] | "\(.width)"')
      if [ "$x" -ge "$((mon - THRESHOLD))" ] && [ "$y" -le "$THRESHOLD" ]; then
        if [ "$in_corner" -eq 0 ]; then
          in_corner=1
          corner_start=$(($(date +%s%N)/1000000))
        else
          now=$(($(date +%s%N)/1000000))
          if [ "$((now - corner_start))" -ge "$DWELL_MS" ]; then
            loginctl lock-session
            in_corner=0
            sleep 2
          fi
        fi
      else
        in_corner=0
      fi
      sleep "$POLL"
    done
  '';
in
{
  imports = [
    ./global
    ./features/essentials
    ./features/emacs
    ./features/cli
    ./features/llm
    ./features/bitwarden
    ./features/rclone
    ./features/desktop/common
    ./features/desktop/dark-theme.nix
    ./features/desktop/hyprlock.nix
    ./features/desktop/hypridle.nix
    ./linux
  ];

  # Hyprland ウィンドウマネージャー設定
  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      monitor = [ ",preferred,auto,1" ];

      "$mod" = "SUPER";

      bind = [
        "$mod, Return, exec, wezterm"
        "$mod, Q, killactive,"
        "$mod SHIFT, E, exit,"
        "$mod, H, movefocus, l"
        "$mod, L, movefocus, r"
        "$mod, K, movefocus, u"
        "$mod, J, movefocus, d"
        "$mod SHIFT, H, movewindow, l"
        "$mod SHIFT, L, movewindow, r"
        "$mod SHIFT, K, movewindow, u"
        "$mod SHIFT, J, movewindow, d"
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod, F, fullscreen, 0"
        "$mod SHIFT, F, togglefloating,"
        # スクリーンショット
        ", Print, exec, grimblast copy area"
        (
          "$mod, D, exec, "
          + lib.getExe (mkMenu [
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
          ])
        )
        (
          "$mod, E, exec, "
          + lib.getExe (mkMenu [
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
          ])
        )
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      general = {
        gaps_in = 4;
        gaps_out = 8;
        border_size = 2;
      };

      decoration = {
        rounding = 8;
      };

      input = {
        kb_layout = "us";
        follow_mouse = 1;
      };

      misc = {
        disable_hyprland_logo = true;
        force_default_wallpaper = 0;
      };

      exec-once = [
        "fcitx5 -d" # 日本語入力デーモン
        "${hotCornerScript}" # 右上ホットコーナー → ロック
      ];
    };
  };

  # スクリーンショットツール
  home.packages = with pkgs; [
    grimblast # スクリーンショット (Hyprland用)
    wl-clipboard # Wayland クリップボード
    hyprpaper # 壁紙
    wofi # アプリランチャー
    waybar # ステータスバー
  ];

  systemd.user.startServices = "sd-switch";
}
