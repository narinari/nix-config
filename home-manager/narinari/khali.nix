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
    ./features/bitwarden
    ./features/rclone
    ./features/desktop/common
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
