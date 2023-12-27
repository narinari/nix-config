{ config, lib, pkgs, ... }: {
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
    extraConfig = ''
      return {
        font = wezterm.font_with_fallback {
          { family = 'BerkeleyMono Nerd Font', assume_emoji_presentation = false},
          { family = 'IBM Plex Sans JP', assume_emoji_presentation = false},
          { family = 'Symbols Nerd Font Mono', assume_emoji_presentation = false},
          { family = 'Apple Color Emoji', assume_emoji_presentation = true},
          { family = 'Noto Emoji', assume_emoji_presentation = true},
        },
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
          { key="0", mods="OPT", action=wezterm.action.SendKey { key="0", mods="OPT" } },
          { key="1", mods="OPT", action=wezterm.action.SendKey { key="1", mods="OPT" } },
          { key="2", mods="OPT", action=wezterm.action.SendKey { key="2", mods="OPT" } },
          { key="3", mods="OPT", action=wezterm.action.SendKey { key="3", mods="OPT" } },
          { key="4", mods="OPT", action=wezterm.action.SendKey { key="4", mods="OPT" } },
          { key="5", mods="OPT", action=wezterm.action.SendKey { key="5", mods="OPT" } },
          { key="6", mods="OPT", action=wezterm.action.SendKey { key="6", mods="OPT" } },
          { key="7", mods="OPT", action=wezterm.action.SendKey { key="7", mods="OPT" } },
          { key="8", mods="OPT", action=wezterm.action.SendKey { key="8", mods="OPT" } },
          { key="9", mods="OPT", action=wezterm.action.SendKey { key="9", mods="OPT" } },

          { key="a", mods="OPT", action=wezterm.action.SendKey { key="a", mods="OPT" } },
          { key="b", mods="OPT", action=wezterm.action.SendKey { key="b", mods="OPT" } },
          { key="c", mods="OPT", action=wezterm.action.SendKey { key="c", mods="OPT" } },
          { key="d", mods="OPT", action=wezterm.action.SendKey { key="d", mods="OPT" } },
          { key="e", mods="OPT", action=wezterm.action.SendKey { key="e", mods="OPT" } },
          { key="f", mods="OPT", action=wezterm.action.SendKey { key="f", mods="OPT" } },
          { key="g", mods="OPT", action=wezterm.action.SendKey { key="g", mods="OPT" } },
          { key="h", mods="OPT", action=wezterm.action.SendKey { key="h", mods="OPT" } },
          { key="i", mods="OPT", action=wezterm.action.SendKey { key="i", mods="OPT" } },
          { key="j", mods="OPT", action=wezterm.action.SendKey { key="j", mods="OPT" } },
          { key="k", mods="OPT", action=wezterm.action.SendKey { key="k", mods="OPT" } },
          { key="l", mods="OPT", action=wezterm.action.SendKey { key="l", mods="OPT" } },
          { key="m", mods="OPT", action=wezterm.action.SendKey { key="m", mods="OPT" } },
          { key="n", mods="OPT", action=wezterm.action.SendKey { key="n", mods="OPT" } },
          { key="o", mods="OPT", action=wezterm.action.SendKey { key="o", mods="OPT" } },
          { key="p", mods="OPT", action=wezterm.action.SendKey { key="p", mods="OPT" } },
          { key="q", mods="OPT", action=wezterm.action.SendKey { key="q", mods="OPT" } },
          { key="r", mods="OPT", action=wezterm.action.SendKey { key="r", mods="OPT" } },
          { key="s", mods="OPT", action=wezterm.action.SendKey { key="s", mods="OPT" } },
          { key="t", mods="OPT", action=wezterm.action.SendKey { key="t", mods="OPT" } },
          { key="u", mods="OPT", action=wezterm.action.SendKey { key="u", mods="OPT" } },
          { key="v", mods="OPT", action=wezterm.action.SendKey { key="v", mods="OPT" } },
          { key="w", mods="OPT", action=wezterm.action.SendKey { key="w", mods="OPT" } },
          { key="x", mods="OPT", action=wezterm.action.SendKey { key="x", mods="OPT" } },
          { key="y", mods="OPT", action=wezterm.action.SendKey { key="y", mods="OPT" } },
          { key="z", mods="OPT", action=wezterm.action.SendKey { key="z", mods="OPT" } },

          { key="/", mods="OPT", action=wezterm.action.SendKey { key="/", mods="OPT" } },
          { key=";", mods="OPT", action=wezterm.action.SendKey { key=";", mods="OPT" } },
          { key="backslash", mods="OPT", action=wezterm.action.SendKey { key="backslash", mods="OPT" } },
          { key="space", mods="OPT", action=wezterm.action.SendKey { key="space", mods="OPT" } },
          { key=";", mods="CTRL", action=wezterm.action.SendString "\x18@;" }, -- for emacs in terminal
          { key="j", mods="CTRL", action=wezterm.action.SendString "\x18@j" }, -- for emacs ddskk interminal
        },
      }
    '';
  };
}
