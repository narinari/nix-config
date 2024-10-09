{ config, lib, pkgs, ... }: {
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
    extraConfig = ''
      local act = wezterm.action

      return {
        font = wezterm.font_with_fallback {
          { family = 'SF Mono', assume_emoji_presentation = false},
          { family = 'IBM Plex Sans JP', assume_emoji_presentation = false},
          { family = 'Symbols Nerd Font Mono', assume_emoji_presentation = false},
          { family = 'Apple Color Emoji', assume_emoji_presentation = true},
          { family = 'Noto Emoji', assume_emoji_presentation = true},
        },
        -- treat_east_asian_ambiguous_width_as_wide = true,
        use_ime = true,

        -- Work around https://github.com/wez/wezterm/issues/5990
        front_end = "WebGpu",
        enable_wayland = false,

        color_scheme = "Tokyo Night",
        colors = {
          tab_bar = {
            active_tab = {
              fg_color = "#2E3440",
              bg_color = "#5E81AC"
            }
          }
        },

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

        disable_default_key_bindings = true,
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
          { key="Enter", mods="OPT", action=wezterm.action.SendKey { key="Enter", mods="OPT" } },
          { key="\\", mods="OPT", action=wezterm.action.SendKey { key="\\", mods="OPT" } },
          { key="Space", mods="OPT", action=wezterm.action.SendKey { key="Space", mods="OPT" } },
          { key=";", mods="CTRL", action=wezterm.action.SendString "\x18@;" }, -- for emacs in terminal

          -- for default
          { key = 'Tab', mods = 'CTRL', action = act.ActivateTabRelative(1) },
          { key = 'Tab', mods = 'SHIFT|CTRL', action = act.ActivateTabRelative(-1) },
          { key = 'Enter', mods = 'SUPER', action = act.ToggleFullScreen },
          { key = '!', mods = 'SUPER', action = act.ActivateTab(0) },
          { key = '!', mods = 'SHIFT|SUPER', action = act.ActivateTab(0) },
          { key = '\"', mods = 'ALT|SUPER', action = act.SplitVertical{ domain =  'CurrentPaneDomain' } },
          { key = '\"', mods = 'SHIFT|ALT|SUPER', action = act.SplitVertical{ domain =  'CurrentPaneDomain' } },
          { key = '#', mods = 'SUPER', action = act.ActivateTab(2) },
          { key = '#', mods = 'SHIFT|SUPER', action = act.ActivateTab(2) },
          { key = '$', mods = 'SUPER', action = act.ActivateTab(3) },
          { key = '$', mods = 'SHIFT|SUPER', action = act.ActivateTab(3) },
          { key = '%', mods = 'SUPER', action = act.ActivateTab(4) },
          { key = '%', mods = 'SHIFT|SUPER', action = act.ActivateTab(4) },
          { key = '%', mods = 'ALT|SUPER', action = act.SplitHorizontal{ domain =  'CurrentPaneDomain' } },
          { key = '%', mods = 'SHIFT|ALT|SUPER', action = act.SplitHorizontal{ domain =  'CurrentPaneDomain' } },
          { key = '&', mods = 'SUPER', action = act.ActivateTab(6) },
          { key = '&', mods = 'SHIFT|SUPER', action = act.ActivateTab(6) },
          { key = '\''', mods = 'SHIFT|ALT|SUPER', action = act.SplitVertical{ domain =  'CurrentPaneDomain' } },
          { key = '(', mods = 'SUPER', action = act.ActivateTab(-1) },
          { key = '(', mods = 'SHIFT|SUPER', action = act.ActivateTab(-1) },
          { key = ')', mods = 'SUPER', action = act.ResetFontSize },
          { key = ')', mods = 'SHIFT|SUPER', action = act.ResetFontSize },
          { key = '*', mods = 'SUPER', action = act.ActivateTab(7) },
          { key = '*', mods = 'SHIFT|SUPER', action = act.ActivateTab(7) },
          { key = '+', mods = 'SUPER', action = act.IncreaseFontSize },
          { key = '+', mods = 'SHIFT|SUPER', action = act.IncreaseFontSize },
          { key = '-', mods = 'SUPER', action = act.DecreaseFontSize },
          { key = '-', mods = 'SHIFT|SUPER', action = act.DecreaseFontSize },
          { key = '-', mods = 'SUPER', action = act.DecreaseFontSize },
          { key = '0', mods = 'SUPER', action = act.ResetFontSize },
          { key = '0', mods = 'SHIFT|SUPER', action = act.ResetFontSize },
          { key = '1', mods = 'SHIFT|SUPER', action = act.ActivateTab(0) },
          { key = '1', mods = 'SUPER', action = act.ActivateTab(0) },
          { key = '2', mods = 'SHIFT|SUPER', action = act.ActivateTab(1) },
          { key = '2', mods = 'SUPER', action = act.ActivateTab(1) },
          { key = '3', mods = 'SHIFT|SUPER', action = act.ActivateTab(2) },
          { key = '3', mods = 'SUPER', action = act.ActivateTab(2) },
          { key = '4', mods = 'SHIFT|SUPER', action = act.ActivateTab(3) },
          { key = '4', mods = 'SUPER', action = act.ActivateTab(3) },
          { key = '5', mods = 'SHIFT|SUPER', action = act.ActivateTab(4) },
          { key = '5', mods = 'SHIFT|ALT|SUPER', action = act.SplitHorizontal{ domain =  'CurrentPaneDomain' } },
          { key = '5', mods = 'SUPER', action = act.ActivateTab(4) },
          { key = '6', mods = 'SHIFT|SUPER', action = act.ActivateTab(5) },
          { key = '6', mods = 'SUPER', action = act.ActivateTab(5) },
          { key = '7', mods = 'SHIFT|SUPER', action = act.ActivateTab(6) },
          { key = '7', mods = 'SUPER', action = act.ActivateTab(6) },
          { key = '8', mods = 'SHIFT|SUPER', action = act.ActivateTab(7) },
          { key = '8', mods = 'SUPER', action = act.ActivateTab(7) },
          { key = '9', mods = 'SHIFT|SUPER', action = act.ActivateTab(-1) },
          { key = '9', mods = 'SUPER', action = act.ActivateTab(-1) },
          { key = '=', mods = 'SUPER', action = act.IncreaseFontSize },
          { key = '=', mods = 'SHIFT|SUPER', action = act.IncreaseFontSize },
          { key = '=', mods = 'SUPER', action = act.IncreaseFontSize },
          { key = '@', mods = 'SUPER', action = act.ActivateTab(1) },
          { key = '@', mods = 'SHIFT|SUPER', action = act.ActivateTab(1) },
          { key = 'C', mods = 'SUPER', action = act.CopyTo 'Clipboard' },
          { key = 'C', mods = 'SHIFT|SUPER', action = act.CopyTo 'Clipboard' },
          { key = 'F', mods = 'SUPER', action = act.Search 'CurrentSelectionOrEmptyString' },
          { key = 'F', mods = 'SHIFT|SUPER', action = act.Search 'CurrentSelectionOrEmptyString' },
          { key = 'H', mods = 'SUPER', action = act.HideApplication },
          { key = 'H', mods = 'SHIFT|SUPER', action = act.HideApplication },
          { key = 'K', mods = 'SUPER', action = act.ClearScrollback 'ScrollbackOnly' },
          { key = 'K', mods = 'SHIFT|SUPER', action = act.ClearScrollback 'ScrollbackOnly' },
          { key = 'L', mods = 'SUPER', action = act.ShowDebugOverlay },
          { key = 'L', mods = 'SHIFT|SUPER', action = act.ShowDebugOverlay },
          { key = 'M', mods = 'SUPER', action = act.Hide },
          { key = 'M', mods = 'SHIFT|SUPER', action = act.Hide },
          { key = 'N', mods = 'SUPER', action = act.SpawnWindow },
          { key = 'N', mods = 'SHIFT|SUPER', action = act.SpawnWindow },
          { key = 'P', mods = 'SUPER', action = act.ActivateCommandPalette },
          { key = 'P', mods = 'SHIFT|SUPER', action = act.ActivateCommandPalette },
          { key = 'Q', mods = 'SUPER', action = act.QuitApplication },
          { key = 'Q', mods = 'SHIFT|SUPER', action = act.QuitApplication },
          { key = 'R', mods = 'SUPER', action = act.ReloadConfiguration },
          { key = 'R', mods = 'SHIFT|SUPER', action = act.ReloadConfiguration },
          { key = 'T', mods = 'SUPER', action = act.SpawnTab 'CurrentPaneDomain' },
          { key = 'T', mods = 'SHIFT|SUPER', action = act.SpawnTab 'CurrentPaneDomain' },
          { key = 'U', mods = 'SUPER', action = act.CharSelect{ copy_on_select = true, copy_to =  'ClipboardAndPrimarySelection' } },
          { key = 'U', mods = 'SHIFT|SUPER', action = act.CharSelect{ copy_on_select = true, copy_to =  'ClipboardAndPrimarySelection' } },
          { key = 'V', mods = 'SUPER', action = act.PasteFrom 'Clipboard' },
          { key = 'V', mods = 'SHIFT|SUPER', action = act.PasteFrom 'Clipboard' },
          { key = 'W', mods = 'SUPER', action = act.CloseCurrentTab{ confirm = true } },
          { key = 'W', mods = 'SHIFT|SUPER', action = act.CloseCurrentTab{ confirm = true } },
          { key = 'X', mods = 'SUPER', action = act.ActivateCopyMode },
          { key = 'X', mods = 'SHIFT|SUPER', action = act.ActivateCopyMode },
          { key = 'Z', mods = 'SUPER', action = act.TogglePaneZoomState },
          { key = 'Z', mods = 'SHIFT|SUPER', action = act.TogglePaneZoomState },
          { key = '[', mods = 'SHIFT|SUPER', action = act.ActivateTabRelative(-1) },
          { key = ']', mods = 'SHIFT|SUPER', action = act.ActivateTabRelative(1) },
          { key = '^', mods = 'SUPER', action = act.ActivateTab(5) },
          { key = '^', mods = 'SHIFT|SUPER', action = act.ActivateTab(5) },
          { key = '_', mods = 'SUPER', action = act.DecreaseFontSize },
          { key = '_', mods = 'SHIFT|SUPER', action = act.DecreaseFontSize },
          { key = 'c', mods = 'SHIFT|SUPER', action = act.CopyTo 'Clipboard' },
          { key = 'c', mods = 'SUPER', action = act.CopyTo 'Clipboard' },
          { key = 'f', mods = 'SHIFT|SUPER', action = act.Search 'CurrentSelectionOrEmptyString' },
          { key = 'f', mods = 'SUPER', action = act.Search 'CurrentSelectionOrEmptyString' },
          { key = 'h', mods = 'SHIFT|SUPER', action = act.HideApplication },
          { key = 'h', mods = 'SUPER', action = act.HideApplication },
          { key = 'k', mods = 'SHIFT|SUPER', action = act.ClearScrollback 'ScrollbackOnly' },
          { key = 'k', mods = 'SUPER', action = act.ClearScrollback 'ScrollbackOnly' },
          { key = 'l', mods = 'SHIFT|SUPER', action = act.ShowDebugOverlay },
          { key = 'm', mods = 'SHIFT|SUPER', action = act.Hide },
          { key = 'm', mods = 'SUPER', action = act.Hide },
          { key = 'n', mods = 'SHIFT|SUPER', action = act.SpawnWindow },
          { key = 'n', mods = 'SUPER', action = act.SpawnWindow },
          { key = 'p', mods = 'SHIFT|SUPER', action = act.ActivateCommandPalette },
          { key = 'q', mods = 'SHIFT|SUPER', action = act.QuitApplication },
          { key = 'q', mods = 'SUPER', action = act.QuitApplication },
          { key = 'r', mods = 'SHIFT|SUPER', action = act.ReloadConfiguration },
          { key = 'r', mods = 'SUPER', action = act.ReloadConfiguration },
          { key = 't', mods = 'SHIFT|SUPER', action = act.SpawnTab 'CurrentPaneDomain' },
          { key = 't', mods = 'SUPER', action = act.SpawnTab 'CurrentPaneDomain' },
          { key = 'u', mods = 'SHIFT|SUPER', action = act.CharSelect{ copy_on_select = true, copy_to =  'ClipboardAndPrimarySelection' } },
          { key = 'v', mods = 'SHIFT|SUPER', action = act.PasteFrom 'Clipboard' },
          { key = 'v', mods = 'SUPER', action = act.PasteFrom 'Clipboard' },
          { key = 'w', mods = 'SHIFT|SUPER', action = act.CloseCurrentTab{ confirm = true } },
          { key = 'w', mods = 'SUPER', action = act.CloseCurrentTab{ confirm = true } },
          { key = 'x', mods = 'SHIFT|SUPER', action = act.ActivateCopyMode },
          { key = 'z', mods = 'SHIFT|SUPER', action = act.TogglePaneZoomState },
          { key = '{', mods = 'SUPER', action = act.ActivateTabRelative(-1) },
          { key = '{', mods = 'SHIFT|SUPER', action = act.ActivateTabRelative(-1) },
          { key = '}', mods = 'SUPER', action = act.ActivateTabRelative(1) },
          { key = '}', mods = 'SHIFT|SUPER', action = act.ActivateTabRelative(1) },
          { key = 'phys:Space', mods = 'SHIFT|SUPER', action = act.QuickSelect },
          { key = 'PageUp', mods = 'SHIFT', action = act.ScrollByPage(-1) },
          { key = 'PageUp', mods = 'SUPER', action = act.ActivateTabRelative(-1) },
          { key = 'PageUp', mods = 'SHIFT|SUPER', action = act.MoveTabRelative(-1) },
          { key = 'PageDown', mods = 'SHIFT', action = act.ScrollByPage(1) },
          { key = 'PageDown', mods = 'SUPER', action = act.ActivateTabRelative(1) },
          { key = 'PageDown', mods = 'SHIFT|SUPER', action = act.MoveTabRelative(1) },
          { key = 'LeftArrow', mods = 'SHIFT|SUPER', action = act.ActivatePaneDirection 'Left' },
          { key = 'LeftArrow', mods = 'SHIFT|ALT|SUPER', action = act.AdjustPaneSize{ 'Left', 1 } },
          { key = 'RightArrow', mods = 'SHIFT|SUPER', action = act.ActivatePaneDirection 'Right' },
          { key = 'RightArrow', mods = 'SHIFT|ALT|SUPER', action = act.AdjustPaneSize{ 'Right', 1 } },
          { key = 'UpArrow', mods = 'SHIFT|SUPER', action = act.ActivatePaneDirection 'Up' },
          { key = 'UpArrow', mods = 'SHIFT|ALT|SUPER', action = act.AdjustPaneSize{ 'Up', 1 } },
          { key = 'DownArrow', mods = 'SHIFT|SUPER', action = act.ActivatePaneDirection 'Down' },
          { key = 'DownArrow', mods = 'SHIFT|ALT|SUPER', action = act.AdjustPaneSize{ 'Down', 1 } },
          { key = 'Copy', mods = 'NONE', action = act.CopyTo 'Clipboard' },
          { key = 'Paste', mods = 'NONE', action = act.PasteFrom 'Clipboard' },
        },
      }
        --[[ default key map
        keys = {
          { key = 'Tab', mods = 'CTRL', action = act.ActivateTabRelative(1) },
          { key = 'Tab', mods = 'SHIFT|CTRL', action = act.ActivateTabRelative(-1) },
          { key = 'Enter', mods = 'ALT', action = act.ToggleFullScreen },
          { key = '!', mods = 'CTRL', action = act.ActivateTab(0) },
          { key = '!', mods = 'SHIFT|CTRL', action = act.ActivateTab(0) },
          { key = '\"', mods = 'ALT|CTRL', action = act.SplitVertical{ domain =  'CurrentPaneDomain' } },
          { key = '\"', mods = 'SHIFT|ALT|CTRL', action = act.SplitVertical{ domain =  'CurrentPaneDomain' } },
          { key = '#', mods = 'CTRL', action = act.ActivateTab(2) },
          { key = '#', mods = 'SHIFT|CTRL', action = act.ActivateTab(2) },
          { key = '$', mods = 'CTRL', action = act.ActivateTab(3) },
          { key = '$', mods = 'SHIFT|CTRL', action = act.ActivateTab(3) },
          { key = '%', mods = 'CTRL', action = act.ActivateTab(4) },
          { key = '%', mods = 'SHIFT|CTRL', action = act.ActivateTab(4) },
          { key = '%', mods = 'ALT|CTRL', action = act.SplitHorizontal{ domain =  'CurrentPaneDomain' } },
          { key = '%', mods = 'SHIFT|ALT|CTRL', action = act.SplitHorizontal{ domain =  'CurrentPaneDomain' } },
          { key = '&', mods = 'CTRL', action = act.ActivateTab(6) },
          { key = '&', mods = 'SHIFT|CTRL', action = act.ActivateTab(6) },
          { key = '\''', mods = 'SHIFT|ALT|CTRL', action = act.SplitVertical{ domain =  'CurrentPaneDomain' } }, -- NOTE: replace triple-quotes to double-quotes at uncomment
          { key = '(', mods = 'CTRL', action = act.ActivateTab(-1) },
          { key = '(', mods = 'SHIFT|CTRL', action = act.ActivateTab(-1) },
          { key = ')', mods = 'CTRL', action = act.ResetFontSize },
          { key = ')', mods = 'SHIFT|CTRL', action = act.ResetFontSize },
          { key = '*', mods = 'CTRL', action = act.ActivateTab(7) },
          { key = '*', mods = 'SHIFT|CTRL', action = act.ActivateTab(7) },
          { key = '+', mods = 'CTRL', action = act.IncreaseFontSize },
          { key = '+', mods = 'SHIFT|CTRL', action = act.IncreaseFontSize },
          { key = '-', mods = 'CTRL', action = act.DecreaseFontSize },
          { key = '-', mods = 'SHIFT|CTRL', action = act.DecreaseFontSize },
          { key = '-', mods = 'SUPER', action = act.DecreaseFontSize },
          { key = '0', mods = 'CTRL', action = act.ResetFontSize },
          { key = '0', mods = 'SHIFT|CTRL', action = act.ResetFontSize },
          { key = '0', mods = 'SUPER', action = act.ResetFontSize },
          { key = '1', mods = 'SHIFT|CTRL', action = act.ActivateTab(0) },
          { key = '1', mods = 'SUPER', action = act.ActivateTab(0) },
          { key = '2', mods = 'SHIFT|CTRL', action = act.ActivateTab(1) },
          { key = '2', mods = 'SUPER', action = act.ActivateTab(1) },
          { key = '3', mods = 'SHIFT|CTRL', action = act.ActivateTab(2) },
          { key = '3', mods = 'SUPER', action = act.ActivateTab(2) },
          { key = '4', mods = 'SHIFT|CTRL', action = act.ActivateTab(3) },
          { key = '4', mods = 'SUPER', action = act.ActivateTab(3) },
          { key = '5', mods = 'SHIFT|CTRL', action = act.ActivateTab(4) },
          { key = '5', mods = 'SHIFT|ALT|CTRL', action = act.SplitHorizontal{ domain =  'CurrentPaneDomain' } },
          { key = '5', mods = 'SUPER', action = act.ActivateTab(4) },
          { key = '6', mods = 'SHIFT|CTRL', action = act.ActivateTab(5) },
          { key = '6', mods = 'SUPER', action = act.ActivateTab(5) },
          { key = '7', mods = 'SHIFT|CTRL', action = act.ActivateTab(6) },
          { key = '7', mods = 'SUPER', action = act.ActivateTab(6) },
          { key = '8', mods = 'SHIFT|CTRL', action = act.ActivateTab(7) },
          { key = '8', mods = 'SUPER', action = act.ActivateTab(7) },
          { key = '9', mods = 'SHIFT|CTRL', action = act.ActivateTab(-1) },
          { key = '9', mods = 'SUPER', action = act.ActivateTab(-1) },
          { key = '=', mods = 'CTRL', action = act.IncreaseFontSize },
          { key = '=', mods = 'SHIFT|CTRL', action = act.IncreaseFontSize },
          { key = '=', mods = 'SUPER', action = act.IncreaseFontSize },
          { key = '@', mods = 'CTRL', action = act.ActivateTab(1) },
          { key = '@', mods = 'SHIFT|CTRL', action = act.ActivateTab(1) },
          { key = 'C', mods = 'CTRL', action = act.CopyTo 'Clipboard' },
          { key = 'C', mods = 'SHIFT|CTRL', action = act.CopyTo 'Clipboard' },
          { key = 'F', mods = 'CTRL', action = act.Search 'CurrentSelectionOrEmptyString' },
          { key = 'F', mods = 'SHIFT|CTRL', action = act.Search 'CurrentSelectionOrEmptyString' },
          { key = 'H', mods = 'CTRL', action = act.HideApplication },
          { key = 'H', mods = 'SHIFT|CTRL', action = act.HideApplication },
          { key = 'K', mods = 'CTRL', action = act.ClearScrollback 'ScrollbackOnly' },
          { key = 'K', mods = 'SHIFT|CTRL', action = act.ClearScrollback 'ScrollbackOnly' },
          { key = 'L', mods = 'CTRL', action = act.ShowDebugOverlay },
          { key = 'L', mods = 'SHIFT|CTRL', action = act.ShowDebugOverlay },
          { key = 'M', mods = 'CTRL', action = act.Hide },
          { key = 'M', mods = 'SHIFT|CTRL', action = act.Hide },
          { key = 'N', mods = 'CTRL', action = act.SpawnWindow },
          { key = 'N', mods = 'SHIFT|CTRL', action = act.SpawnWindow },
          { key = 'P', mods = 'CTRL', action = act.ActivateCommandPalette },
          { key = 'P', mods = 'SHIFT|CTRL', action = act.ActivateCommandPalette },
          { key = 'Q', mods = 'CTRL', action = act.QuitApplication },
          { key = 'Q', mods = 'SHIFT|CTRL', action = act.QuitApplication },
          { key = 'R', mods = 'CTRL', action = act.ReloadConfiguration },
          { key = 'R', mods = 'SHIFT|CTRL', action = act.ReloadConfiguration },
          { key = 'T', mods = 'CTRL', action = act.SpawnTab 'CurrentPaneDomain' },
          { key = 'T', mods = 'SHIFT|CTRL', action = act.SpawnTab 'CurrentPaneDomain' },
          { key = 'U', mods = 'CTRL', action = act.CharSelect{ copy_on_select = true, copy_to =  'ClipboardAndPrimarySelection' } },
          { key = 'U', mods = 'SHIFT|CTRL', action = act.CharSelect{ copy_on_select = true, copy_to =  'ClipboardAndPrimarySelection' } },
          { key = 'V', mods = 'CTRL', action = act.PasteFrom 'Clipboard' },
          { key = 'V', mods = 'SHIFT|CTRL', action = act.PasteFrom 'Clipboard' },
          { key = 'W', mods = 'CTRL', action = act.CloseCurrentTab{ confirm = true } },
          { key = 'W', mods = 'SHIFT|CTRL', action = act.CloseCurrentTab{ confirm = true } },
          { key = 'X', mods = 'CTRL', action = act.ActivateCopyMode },
          { key = 'X', mods = 'SHIFT|CTRL', action = act.ActivateCopyMode },
          { key = 'Z', mods = 'CTRL', action = act.TogglePaneZoomState },
          { key = 'Z', mods = 'SHIFT|CTRL', action = act.TogglePaneZoomState },
          { key = '[', mods = 'SHIFT|SUPER', action = act.ActivateTabRelative(-1) },
          { key = ']', mods = 'SHIFT|SUPER', action = act.ActivateTabRelative(1) },
          { key = '^', mods = 'CTRL', action = act.ActivateTab(5) },
          { key = '^', mods = 'SHIFT|CTRL', action = act.ActivateTab(5) },
          { key = '_', mods = 'CTRL', action = act.DecreaseFontSize },
          { key = '_', mods = 'SHIFT|CTRL', action = act.DecreaseFontSize },
          { key = 'c', mods = 'SHIFT|CTRL', action = act.CopyTo 'Clipboard' },
          { key = 'c', mods = 'SUPER', action = act.CopyTo 'Clipboard' },
          { key = 'f', mods = 'SHIFT|CTRL', action = act.Search 'CurrentSelectionOrEmptyString' },
          { key = 'f', mods = 'SUPER', action = act.Search 'CurrentSelectionOrEmptyString' },
          { key = 'h', mods = 'SHIFT|CTRL', action = act.HideApplication },
          { key = 'h', mods = 'SUPER', action = act.HideApplication },
          { key = 'k', mods = 'SHIFT|CTRL', action = act.ClearScrollback 'ScrollbackOnly' },
          { key = 'k', mods = 'SUPER', action = act.ClearScrollback 'ScrollbackOnly' },
          { key = 'l', mods = 'SHIFT|CTRL', action = act.ShowDebugOverlay },
          { key = 'm', mods = 'SHIFT|CTRL', action = act.Hide },
          { key = 'm', mods = 'SUPER', action = act.Hide },
          { key = 'n', mods = 'SHIFT|CTRL', action = act.SpawnWindow },
          { key = 'n', mods = 'SUPER', action = act.SpawnWindow },
          { key = 'p', mods = 'SHIFT|CTRL', action = act.ActivateCommandPalette },
          { key = 'q', mods = 'SHIFT|CTRL', action = act.QuitApplication },
          { key = 'q', mods = 'SUPER', action = act.QuitApplication },
          { key = 'r', mods = 'SHIFT|CTRL', action = act.ReloadConfiguration },
          { key = 'r', mods = 'SUPER', action = act.ReloadConfiguration },
          { key = 't', mods = 'SHIFT|CTRL', action = act.SpawnTab 'CurrentPaneDomain' },
          { key = 't', mods = 'SUPER', action = act.SpawnTab 'CurrentPaneDomain' },
          { key = 'u', mods = 'SHIFT|CTRL', action = act.CharSelect{ copy_on_select = true, copy_to =  'ClipboardAndPrimarySelection' } },
          { key = 'v', mods = 'SHIFT|CTRL', action = act.PasteFrom 'Clipboard' },
          { key = 'v', mods = 'SUPER', action = act.PasteFrom 'Clipboard' },
          { key = 'w', mods = 'SHIFT|CTRL', action = act.CloseCurrentTab{ confirm = true } },
          { key = 'w', mods = 'SUPER', action = act.CloseCurrentTab{ confirm = true } },
          { key = 'x', mods = 'SHIFT|CTRL', action = act.ActivateCopyMode },
          { key = 'z', mods = 'SHIFT|CTRL', action = act.TogglePaneZoomState },
          { key = '{', mods = 'SUPER', action = act.ActivateTabRelative(-1) },
          { key = '{', mods = 'SHIFT|SUPER', action = act.ActivateTabRelative(-1) },
          { key = '}', mods = 'SUPER', action = act.ActivateTabRelative(1) },
          { key = '}', mods = 'SHIFT|SUPER', action = act.ActivateTabRelative(1) },
          { key = 'phys:Space', mods = 'SHIFT|CTRL', action = act.QuickSelect },
          { key = 'PageUp', mods = 'SHIFT', action = act.ScrollByPage(-1) },
          { key = 'PageUp', mods = 'CTRL', action = act.ActivateTabRelative(-1) },
          { key = 'PageUp', mods = 'SHIFT|CTRL', action = act.MoveTabRelative(-1) },
          { key = 'PageDown', mods = 'SHIFT', action = act.ScrollByPage(1) },
          { key = 'PageDown', mods = 'CTRL', action = act.ActivateTabRelative(1) },
          { key = 'PageDown', mods = 'SHIFT|CTRL', action = act.MoveTabRelative(1) },
          { key = 'LeftArrow', mods = 'SHIFT|CTRL', action = act.ActivatePaneDirection 'Left' },
          { key = 'LeftArrow', mods = 'SHIFT|ALT|CTRL', action = act.AdjustPaneSize{ 'Left', 1 } },
          { key = 'RightArrow', mods = 'SHIFT|CTRL', action = act.ActivatePaneDirection 'Right' },
          { key = 'RightArrow', mods = 'SHIFT|ALT|CTRL', action = act.AdjustPaneSize{ 'Right', 1 } },
          { key = 'UpArrow', mods = 'SHIFT|CTRL', action = act.ActivatePaneDirection 'Up' },
          { key = 'UpArrow', mods = 'SHIFT|ALT|CTRL', action = act.AdjustPaneSize{ 'Up', 1 } },
          { key = 'DownArrow', mods = 'SHIFT|CTRL', action = act.ActivatePaneDirection 'Down' },
          { key = 'DownArrow', mods = 'SHIFT|ALT|CTRL', action = act.AdjustPaneSize{ 'Down', 1 } },
          { key = 'Copy', mods = 'NONE', action = act.CopyTo 'Clipboard' },
          { key = 'Paste', mods = 'NONE', action = act.PasteFrom 'Clipboard' },
        },

        key_tables = {
          copy_mode = {
            { key = 'Tab', mods = 'NONE', action = act.CopyMode 'MoveForwardWord' },
            { key = 'Tab', mods = 'SHIFT', action = act.CopyMode 'MoveBackwardWord' },
            { key = 'Enter', mods = 'NONE', action = act.CopyMode 'MoveToStartOfNextLine' },
            { key = 'Escape', mods = 'NONE', action = act.CopyMode 'Close' },
            { key = 'Space', mods = 'NONE', action = act.CopyMode{ SetSelectionMode =  'Cell' } },
            { key = '$', mods = 'NONE', action = act.CopyMode 'MoveToEndOfLineContent' },
            { key = '$', mods = 'SHIFT', action = act.CopyMode 'MoveToEndOfLineContent' },
            { key = ',', mods = 'NONE', action = act.CopyMode 'JumpReverse' },
            { key = '0', mods = 'NONE', action = act.CopyMode 'MoveToStartOfLine' },
            { key = ';', mods = 'NONE', action = act.CopyMode 'JumpAgain' },
            { key = 'F', mods = 'NONE', action = act.CopyMode{ JumpBackward = { prev_char = false } } },
            { key = 'F', mods = 'SHIFT', action = act.CopyMode{ JumpBackward = { prev_char = false } } },
            { key = 'G', mods = 'NONE', action = act.CopyMode 'MoveToScrollbackBottom' },
            { key = 'G', mods = 'SHIFT', action = act.CopyMode 'MoveToScrollbackBottom' },
            { key = 'H', mods = 'NONE', action = act.CopyMode 'MoveToViewportTop' },
            { key = 'H', mods = 'SHIFT', action = act.CopyMode 'MoveToViewportTop' },
            { key = 'L', mods = 'NONE', action = act.CopyMode 'MoveToViewportBottom' },
            { key = 'L', mods = 'SHIFT', action = act.CopyMode 'MoveToViewportBottom' },
            { key = 'M', mods = 'NONE', action = act.CopyMode 'MoveToViewportMiddle' },
            { key = 'M', mods = 'SHIFT', action = act.CopyMode 'MoveToViewportMiddle' },
            { key = 'O', mods = 'NONE', action = act.CopyMode 'MoveToSelectionOtherEndHoriz' },
            { key = 'O', mods = 'SHIFT', action = act.CopyMode 'MoveToSelectionOtherEndHoriz' },
            { key = 'T', mods = 'NONE', action = act.CopyMode{ JumpBackward = { prev_char = true } } },
            { key = 'T', mods = 'SHIFT', action = act.CopyMode{ JumpBackward = { prev_char = true } } },
            { key = 'V', mods = 'NONE', action = act.CopyMode{ SetSelectionMode =  'Line' } },
            { key = 'V', mods = 'SHIFT', action = act.CopyMode{ SetSelectionMode =  'Line' } },
            { key = '^', mods = 'NONE', action = act.CopyMode 'MoveToStartOfLineContent' },
            { key = '^', mods = 'SHIFT', action = act.CopyMode 'MoveToStartOfLineContent' },
            { key = 'b', mods = 'NONE', action = act.CopyMode 'MoveBackwardWord' },
            { key = 'b', mods = 'ALT', action = act.CopyMode 'MoveBackwardWord' },
            { key = 'b', mods = 'CTRL', action = act.CopyMode 'PageUp' },
            { key = 'c', mods = 'CTRL', action = act.CopyMode 'Close' },
            { key = 'd', mods = 'CTRL', action = act.CopyMode{ MoveByPage = (0.5) } },
            { key = 'e', mods = 'NONE', action = act.CopyMode 'MoveForwardWordEnd' },
            { key = 'f', mods = 'NONE', action = act.CopyMode{ JumpForward = { prev_char = false } } },
            { key = 'f', mods = 'ALT', action = act.CopyMode 'MoveForwardWord' },
            { key = 'f', mods = 'CTRL', action = act.CopyMode 'PageDown' },
            { key = 'g', mods = 'NONE', action = act.CopyMode 'MoveToScrollbackTop' },
            { key = 'g', mods = 'CTRL', action = act.CopyMode 'Close' },
            { key = 'h', mods = 'NONE', action = act.CopyMode 'MoveLeft' },
            { key = 'j', mods = 'NONE', action = act.CopyMode 'MoveDown' },
            { key = 'k', mods = 'NONE', action = act.CopyMode 'MoveUp' },
            { key = 'l', mods = 'NONE', action = act.CopyMode 'MoveRight' },
            { key = 'm', mods = 'ALT', action = act.CopyMode 'MoveToStartOfLineContent' },
            { key = 'o', mods = 'NONE', action = act.CopyMode 'MoveToSelectionOtherEnd' },
            { key = 'q', mods = 'NONE', action = act.CopyMode 'Close' },
            { key = 't', mods = 'NONE', action = act.CopyMode{ JumpForward = { prev_char = true } } },
            { key = 'u', mods = 'CTRL', action = act.CopyMode{ MoveByPage = (-0.5) } },
            { key = 'v', mods = 'NONE', action = act.CopyMode{ SetSelectionMode =  'Cell' } },
            { key = 'v', mods = 'CTRL', action = act.CopyMode{ SetSelectionMode =  'Block' } },
            { key = 'w', mods = 'NONE', action = act.CopyMode 'MoveForwardWord' },
            { key = 'y', mods = 'NONE', action = act.Multiple{ { CopyTo =  'ClipboardAndPrimarySelection' }, { CopyMode =  'Close' } } },
            { key = 'PageUp', mods = 'NONE', action = act.CopyMode 'PageUp' },
            { key = 'PageDown', mods = 'NONE', action = act.CopyMode 'PageDown' },
            { key = 'End', mods = 'NONE', action = act.CopyMode 'MoveToEndOfLineContent' },
            { key = 'Home', mods = 'NONE', action = act.CopyMode 'MoveToStartOfLine' },
            { key = 'LeftArrow', mods = 'NONE', action = act.CopyMode 'MoveLeft' },
            { key = 'LeftArrow', mods = 'ALT', action = act.CopyMode 'MoveBackwardWord' },
            { key = 'RightArrow', mods = 'NONE', action = act.CopyMode 'MoveRight' },
            { key = 'RightArrow', mods = 'ALT', action = act.CopyMode 'MoveForwardWord' },
            { key = 'UpArrow', mods = 'NONE', action = act.CopyMode 'MoveUp' },
            { key = 'DownArrow', mods = 'NONE', action = act.CopyMode 'MoveDown' },
          },

          search_mode = {
            { key = 'Enter', mods = 'NONE', action = act.CopyMode 'PriorMatch' },
            { key = 'Escape', mods = 'NONE', action = act.CopyMode 'Close' },
            { key = 'n', mods = 'CTRL', action = act.CopyMode 'NextMatch' },
            { key = 'p', mods = 'CTRL', action = act.CopyMode 'PriorMatch' },
            { key = 'r', mods = 'CTRL', action = act.CopyMode 'CycleMatchType' },
            { key = 'u', mods = 'CTRL', action = act.CopyMode 'ClearPattern' },
            { key = 'PageUp', mods = 'NONE', action = act.CopyMode 'PriorMatchPage' },
            { key = 'PageDown', mods = 'NONE', action = act.CopyMode 'NextMatchPage' },
            { key = 'UpArrow', mods = 'NONE', action = act.CopyMode 'PriorMatch' },
            { key = 'DownArrow', mods = 'NONE', action = act.CopyMode 'NextMatch' },
          },
      ]]
    '';
  };
}
