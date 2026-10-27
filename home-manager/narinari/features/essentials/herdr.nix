{ pkgs, ... }:
let
  toml = pkgs.formats.toml { };
in
{
  home.packages = [ pkgs.herdr ];

  # キーバインドは tmux.nix に揃える (対応表: docs/terminal-herdr-ghostty.md)
  # 検証: herdr config check
  xdg.configFile."herdr/config.toml".source = toml.generate "herdr-config.toml" {
    # config.toml は read-only なので初回 onboarding の保存が失敗する。
    # agent integration は nix 側で宣言する (pkgs/herdr-integrations)
    onboarding = false;

    keys = {
      prefix = "ctrl+q";

      # | で左右分割, - で上下分割
      split_vertical = [
        "prefix+v"
        "prefix+|"
      ];
      split_horizontal = "prefix+minus";

      # ウィンドウ (= herdr のタブ) 移動
      previous_tab = [
        "prefix+p"
        "prefix+ctrl+h"
        "ctrl+shift+tab"
      ];
      next_tab = [
        "prefix+n"
        "prefix+ctrl+l"
        "ctrl+tab"
      ];
      rename_tab = [
        "prefix+shift+t"
        "prefix+comma"
      ];
      close_tab = [
        "prefix+shift+x"
        "prefix+ampersand"
      ];

      # H/J/K/L でリサイズ (既定の swap_pane_* は外す)
      resize_pane_left = "prefix+shift+h";
      resize_pane_down = "prefix+shift+j";
      resize_pane_up = "prefix+shift+k";
      resize_pane_right = "prefix+shift+l";
      swap_pane_left = "";
      swap_pane_down = "";
      swap_pane_up = "";
      swap_pane_right = "";

      reload_config = "prefix+r";
      resize_mode = "prefix+shift+r";

      # セッション (= herdr のワークスペース) の作成, 移動
      new_workspace = "alt+shift+c";
      next_workspace = "alt+l";
      previous_workspace = "alt+u";
      goto = "alt+e";
      workspace_picker = [
        "prefix+w"
        "prefix+ctrl+j"
      ];

      detach = "prefix+d";

      # launch
      command = [
        {
          key = "prefix+g";
          type = "pane";
          command = "zsh -c go_dev";
          description = "go_dev";
        }
        {
          key = "prefix+m";
          type = "popup";
          command = "~/bin/menu-fzf.zsh";
          description = "menu-fzf";
        }
      ];
    };
  };
}
