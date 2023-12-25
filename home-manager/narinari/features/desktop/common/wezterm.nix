{ config, lib, pkgs, ... }: {
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
    extraConfig = ''
      return {
        font = wezterm.font 'BerkeleyMono Nerd Font',
        use_ime = true,
        color_scheme = "nord",
        allow_square_glyphs_to_overflow_width = "Always",
        adjust_window_size_when_changing_font_size = false,
        warn_about_missing_glyphs = true,
        window_padding = {
          left = 0,
          right = 0,
          top = 0,
          bottom = 0,
        },
        window_close_confirmation = 'NeverPrompt',
        keys = {
          {key=";",mods="CTRL",action=wezterm.action.SendString "\x18@;"}, -- for emacs in terminal
          {key="j",mods="CTRL",action=wezterm.action.SendString "\x18@j"}, -- for emacs ddskk interminal
        },
      }
    '';
  };
}
