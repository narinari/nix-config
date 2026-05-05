{ pkgs, ... }:

{
  home.packages = with pkgs; [
    xwayland-satellite # niri の XWayland サポート
    swaybg # 壁紙 (hyprpaper の niri 版)
    fuzzel # アプリランチャー (niri と相性◯)
  ];

  # niri の設定 (KDL)。
  # niri-flake は使わないため、宣言は xdg.configFile で直接配置。
  xdg.configFile."niri/config.kdl".text = ''
    input {
        keyboard {
            xkb {
                layout "us"
            }
        }
        touchpad {
            tap
            natural-scroll
        }
        mouse {}
    }

    // メインモニター: BenQ EW3280U (4K)。
    // niri は preferred を取ると fractional scale 1.25 を選んでしまうため
    // scale 1.0 を明示してネイティブ 4K で表示する。
    // 30Hz が現状の上限 (HDMI 2.0 帯域問題、ケーブル/ポートで別途対応)。
    output "HDMI-A-2" {
        mode "3840x2160@30.000"
        scale 1.0
        position x=0 y=0
    }

    // RTX2080 側の出力は使わない (Hyprland の `DP-3, disable` 相当)
    output "DP-3" {
        off
    }

    layout {
        gaps 8
        center-focused-column "never"
        preset-column-widths {
            proportion 0.33333
            proportion 0.5
            proportion 0.66667
        }
        default-column-width { proportion 0.5; }
        focus-ring {
            width 2
        }
        border {
            off
        }
    }

    spawn-at-startup "xwayland-satellite"
    spawn-at-startup "noctalia-shell"

    binds {
        Mod+Return       { spawn "wezterm"; }
        Mod+D            { spawn "fuzzel"; }
        Mod+Q            { close-window; }
        Mod+Shift+E      { quit; }

        Mod+H            { focus-column-left; }
        Mod+L            { focus-column-right; }
        Mod+J            { focus-window-down; }
        Mod+K            { focus-window-up; }
        Mod+Shift+H      { move-column-left; }
        Mod+Shift+L      { move-column-right; }
        Mod+Shift+J      { move-window-down; }
        Mod+Shift+K      { move-window-up; }

        Mod+1            { focus-workspace 1; }
        Mod+2            { focus-workspace 2; }
        Mod+3            { focus-workspace 3; }
        Mod+4            { focus-workspace 4; }
        Mod+5            { focus-workspace 5; }
        Mod+Shift+1      { move-column-to-workspace 1; }
        Mod+Shift+2      { move-column-to-workspace 2; }
        Mod+Shift+3      { move-column-to-workspace 3; }
        Mod+Shift+4      { move-column-to-workspace 4; }
        Mod+Shift+5      { move-column-to-workspace 5; }

        Mod+F            { maximize-column; }
        Mod+Shift+F      { fullscreen-window; }

        Print            { screenshot; }
    }
  '';
}
