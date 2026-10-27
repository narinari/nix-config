{ pkgs, ... }:
let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
in
{
  programs.ghostty = {
    enable = true;
    # macOS は Homebrew cask (hosts/common/darwin/homebrew.nix) で入れ、設定だけ管理する
    package = if isDarwin then null else pkgs.ghostty;
    # macOS の Ghostty.app は shell integration を自動注入する (package = null だと HM 側では使えない)
    enableZshIntegration = !isDarwin;

    settings = {
      # wezterm.nix と同じフォールバック順
      font-family = [
        "SF Mono"
        "IBM Plex Sans JP"
        "Symbols Nerd Font Mono"
        (if isDarwin then "Apple Color Emoji" else "Noto Emoji")
      ];
      theme = "TokyoNight Night";

      window-padding-x = 0;
      window-padding-y = 0;
      confirm-close-surface = false;

      # herdr の alt+l / alt+u / alt+e を通す
      macos-option-as-alt = true;

      # wezterm の disable_default_key_bindings と同じく既定を全部外し、
      # Ctrl+Tab や Alt+数字などを herdr / tmux まで素通しする
      keybind = [
        "clear"
      ]
      ++ (
        if isDarwin then
          [
            "super+c=copy_to_clipboard"
            "super+v=paste_from_clipboard"
            "super+n=new_window"
            "super+w=close_surface"
            "super+q=quit"
            "super+enter=toggle_fullscreen"
            "super+equal=increase_font_size:1"
            "super+minus=decrease_font_size:1"
            "super+zero=reset_font_size"
          ]
        else
          [
            "ctrl+shift+c=copy_to_clipboard"
            "ctrl+shift+v=paste_from_clipboard"
            "shift+insert=paste_from_selection"
            "ctrl+shift+n=new_window"
            "ctrl+equal=increase_font_size:1"
            "ctrl+minus=decrease_font_size:1"
            "ctrl+zero=reset_font_size"
          ]
      );
    };
  };
}
