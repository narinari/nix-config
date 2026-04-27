{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.wezterm = {
    enable = true;
    # On macOS, use Homebrew cask version for code-signed app (required for notifications)
    # See: https://github.com/wezterm/wezterm/issues/6731
    package = if pkgs.stdenv.isDarwin then pkgs.emptyDirectory else pkgs.wezterm;
    enableZshIntegration = !pkgs.stdenv.isDarwin;
    extraConfig = ''
      local act = wezterm.action

      -- mainワークスペースのeditorタブに切り替え
      wezterm.on('switch-to-main-editor', function(window, pane)
        window:perform_action(act.SwitchToWorkspace{ name = 'main' }, pane)
        local mux_window = window:mux_window()
        for _, tab in ipairs(mux_window:tabs()) do
          if tab:get_title() == 'editor' then
            tab:activate()
            break
          end
        end
      end)

      -- SSH接続 (hostname入力 → ssh実行)
      wezterm.on('ssh-session', function(window, pane)
        window:perform_action(act.PromptInputLine{
          description = 'SSH hostname:',
          action = wezterm.action_callback(function(inner_window, inner_pane, hostname)
            if hostname and #hostname > 0 then
              inner_window:perform_action(act.SpawnCommandInNewTab{
                args = {'ssh', '-tt', '-q', hostname},
              }, inner_pane)
            end
          end),
        }, pane)
      end)

      -- Tokyo Night カラーパレット
      local TN = {
        bg       = '#1A1B26',
        fg       = '#a9b1d6',
        blue     = '#7aa2f7',
        cyan     = '#7dcfff',
        green    = '#73daca',
        magenta  = '#bb9af7',
        red      = '#f7768e',
        white    = '#c0caf5',
        yellow   = '#e0af68',
        black    = '#414868',
        bblack   = '#2A2F41',
      }

      -- dsquare数字 (Nerd Font double-square digits)
      local dsquare = {
        [0] = '\u{f0e22}',
        [1] = '\u{f0e25}',
        [2] = '\u{f0e28}',
        [3] = '\u{f0e2b}',
        [4] = '\u{f0e32}',
        [5] = '\u{f0e2f}',
        [6] = '\u{f0e34}',
        [7] = '\u{f0e37}',
        [8] = '\u{f0e3a}',
        [9] = '\u{f0e3d}',
      }

      local function dsquare_number(n)
        local result = ""
        local s = tostring(n)
        for i = 1, #s do
          local digit = tonumber(s:sub(i, i))
          result = result .. (dsquare[digit] or s:sub(i, i)) .. ' '
        end
        return result
      end

      -- ステータスバー (tmux tokyo-night status line 移植)
      wezterm.on('update-status', function(window, pane)
        -- 左: ワークスペース名 + leader indicator
        local prefix_icon = '\u{f0942} '
        if window:leader_is_active() then
          prefix_icon = '\u{f00a0} '
        end

        local workspace = window:active_workspace()

        local left = wezterm.format {
          { Background = { Color = TN.blue } },
          { Foreground = { Color = TN.bblack } },
          { Attribute = { Intensity = 'Bold' } },
          { Text = ' ' .. prefix_icon .. workspace .. ' ' },
          { Background = { Color = TN.bg } },
          { Foreground = { Color = TN.blue } },
          { Text = "\u{e0b0}" },
          { Attribute = { Intensity = 'Normal' } },
          { Text = ' ' },
        }
        window:set_left_status(left)

        -- 右: key table indicator + 相対パス
        local right_elements = {}

        local key_table = window:active_key_table()
        if key_table then
          table.insert(right_elements, { Foreground = { Color = TN.yellow } })
          table.insert(right_elements, { Background = { Color = TN.bg } })
          table.insert(right_elements, { Text = "\u{e0b2}" })
          table.insert(right_elements, { Background = { Color = TN.yellow } })
          table.insert(right_elements, { Foreground = { Color = TN.bg } })
          table.insert(right_elements, { Attribute = { Intensity = 'Bold' } })
          table.insert(right_elements, { Text = ' ' .. key_table .. ' ' })
          table.insert(right_elements, { Attribute = { Intensity = 'Normal' } })
        end

        if window:leader_is_active() then
          table.insert(right_elements, { Foreground = { Color = TN.green } })
          table.insert(right_elements, { Background = { Color = TN.bg } })
          table.insert(right_elements, { Text = "\u{e0b2}" })
          table.insert(right_elements, { Background = { Color = TN.green } })
          table.insert(right_elements, { Foreground = { Color = TN.bg } })
          table.insert(right_elements, { Attribute = { Intensity = 'Bold' } })
          table.insert(right_elements, { Text = ' LEADER ' })
          table.insert(right_elements, { Attribute = { Intensity = 'Normal' } })
        end

        local cwd_uri = pane:get_current_working_dir()
        if cwd_uri then
          local cwd = cwd_uri.file_path or ""
          local home = os.getenv('HOME') or ""
          if home ~= "" and cwd:sub(1, #home) == home then
            cwd = '~' .. cwd:sub(#home + 1)
          end
          table.insert(right_elements, { Foreground = { Color = TN.blue } })
          table.insert(right_elements, { Background = { Color = TN.bg } })
          table.insert(right_elements, { Text = ' ' })
          table.insert(right_elements, { Text = "\u{e0b2}" })
          table.insert(right_elements, { Background = { Color = TN.blue } })
          table.insert(right_elements, { Foreground = { Color = TN.bblack } })
          table.insert(right_elements, { Attribute = { Intensity = 'Bold' } })
          table.insert(right_elements, { Text = '  ' .. cwd .. ' ' })
          table.insert(right_elements, { Attribute = { Intensity = 'Normal' } })
        end

        window:set_right_status(wezterm.format(right_elements))
      end)

      -- タブタイトル (tmux dsquare window ID style 移植)
      wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
        local index = tab.tab_index + 1
        local title = tab.active_pane.title
        if #title > 20 then
          title = title:sub(1, 20) .. '\u{2026}'
        end

        local num = dsquare_number(index)
        local process = tab.active_pane.foreground_process_name or ""
        local is_ssh = process:find('ssh') ~= nil
        local icon = is_ssh and '\u{f0ce0} ' or (tab.is_active and ' ' or ' ')

        if tab.is_active then
          return {
            { Background = { Color = TN.bblack } },
            { Foreground = { Color = TN.green } },
            { Text = ' ' .. icon },
            { Foreground = { Color = TN.white } },
            { Attribute = { Intensity = 'Bold' } },
            { Text = num .. title },
            { Attribute = { Intensity = 'Normal' } },
            { Text = ' ' },
          }
        else
          return {
            { Background = { Color = TN.bg } },
            { Foreground = { Color = TN.fg } },
            { Text = ' ' .. icon },
            { Text = num .. title },
            { Text = ' ' },
          }
        end
      end)

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

        macos_forward_to_ime_modifier_mask = "SHIFT|CTRL",

        -- Work around https://github.com/wez/wezterm/issues/5990
        front_end = "WebGpu",
        enable_wayland = false,

        color_scheme = "Tokyo Night",
        use_fancy_tab_bar = false,
        tab_bar_at_bottom = false,
        tab_max_width = 50,
        colors = {
          tab_bar = {
            background = '#1A1B26',
            active_tab = {
              fg_color = '#c0caf5',
              bg_color = '#2A2F41',
              intensity = 'Bold',
            },
            inactive_tab = {
              fg_color = '#a9b1d6',
              bg_color = '#1A1B26',
            },
            inactive_tab_hover = {
              fg_color = '#c0caf5',
              bg_color = '#2A2F41',
            },
            new_tab = {
              fg_color = '#a9b1d6',
              bg_color = '#1A1B26',
            },
            new_tab_hover = {
              fg_color = '#c0caf5',
              bg_color = '#2A2F41',
            },
          },
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

        notification_handling = "AlwaysShow",

        disable_default_key_bindings = true,
        leader = { key = 'q', mods = 'CTRL', timeout_milliseconds = 1000 },
        keys = {
          -- OPT key passthrough for terminal applications
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

          -- === tmux移植: Leader バインド (prefix: Ctrl+Q) ===
          -- ペイン分割
          { key = '|', mods = 'LEADER|SHIFT', action = act.SplitHorizontal{ domain = 'CurrentPaneDomain' } },
          { key = '-', mods = 'LEADER', action = act.SplitVertical{ domain = 'CurrentPaneDomain' } },
          -- ペイン移動 (vim style)
          { key = 'h', mods = 'LEADER', action = act.ActivatePaneDirection 'Left' },
          { key = 'j', mods = 'LEADER', action = act.ActivatePaneDirection 'Down' },
          { key = 'k', mods = 'LEADER', action = act.ActivatePaneDirection 'Up' },
          { key = 'l', mods = 'LEADER', action = act.ActivatePaneDirection 'Right' },
          -- タブ移動
          { key = 'h', mods = 'LEADER|CTRL', action = act.ActivateTabRelative(-1) },
          { key = 'l', mods = 'LEADER|CTRL', action = act.ActivateTabRelative(1) },
          -- ペインリサイズ
          { key = 'H', mods = 'LEADER|SHIFT', action = act.AdjustPaneSize{ 'Left', 5 } },
          { key = 'J', mods = 'LEADER|SHIFT', action = act.AdjustPaneSize{ 'Down', 5 } },
          { key = 'K', mods = 'LEADER|SHIFT', action = act.AdjustPaneSize{ 'Up', 5 } },
          { key = 'L', mods = 'LEADER|SHIFT', action = act.AdjustPaneSize{ 'Right', 5 } },
          -- ワークスペース操作テーブルに入る (one_shot=false で連打可能)
          { key = 'e', mods = 'LEADER', action = act.ActivateKeyTable{ name = 'workspace_nav', one_shot = false, timeout_milliseconds = 3000 } },
          -- 新規ワークスペース
          { key = 'C', mods = 'LEADER|SHIFT', action = act.SwitchToWorkspace{} },
          -- fzfセッションジャンプ
          { key = 's', mods = 'LEADER', action = act.ShowLauncherArgs{ flags = 'FUZZY|WORKSPACES' } },
          -- ペインズーム
          { key = 'z', mods = 'LEADER', action = act.TogglePaneZoomState },
          -- 設定リロード
          { key = 'r', mods = 'LEADER', action = act.ReloadConfiguration },
          -- 外部コマンド (スタブ)
          { key = 'g', mods = 'LEADER', action = act.SpawnCommandInNewTab{ args = {'zsh', '-c', 'go_dev'} } },
          { key = 'm', mods = 'LEADER', action = act.SpawnCommandInNewTab{ args = {'zsh', '-ic', '~/bin/menu-fzf.zsh'} } },
          { key = 'G', mods = 'LEADER|SHIFT', action = act.EmitEvent 'ssh-session' },
          -- Ctrl+Q をターミナルに送信 (emacs用エスケープハッチ)
          { key = 'q', mods = 'LEADER', action = act.SendString '\x11' },

          -- === wezterm固有: タブ操作 ===
          { key = 'Tab', mods = 'CTRL', action = act.ActivateTabRelative(1) },
          { key = 'Tab', mods = 'SHIFT|CTRL', action = act.ActivateTabRelative(-1) },
          { key = 'Enter', mods = 'SUPER', action = act.ToggleFullScreen },
          -- タブ番号選択
          { key = '!', mods = 'SUPER', action = act.ActivateTab(0) },
          { key = '!', mods = 'SHIFT|SUPER', action = act.ActivateTab(0) },
          { key = '#', mods = 'SUPER', action = act.ActivateTab(2) },
          { key = '#', mods = 'SHIFT|SUPER', action = act.ActivateTab(2) },
          { key = '$', mods = 'SUPER', action = act.ActivateTab(3) },
          { key = '$', mods = 'SHIFT|SUPER', action = act.ActivateTab(3) },
          { key = '%', mods = 'SUPER', action = act.ActivateTab(4) },
          { key = '%', mods = 'SHIFT|SUPER', action = act.ActivateTab(4) },
          { key = '&', mods = 'SUPER', action = act.ActivateTab(6) },
          { key = '&', mods = 'SHIFT|SUPER', action = act.ActivateTab(6) },
          { key = '(', mods = 'SUPER', action = act.ActivateTab(-1) },
          { key = '(', mods = 'SHIFT|SUPER', action = act.ActivateTab(-1) },
          { key = '*', mods = 'SUPER', action = act.ActivateTab(7) },
          { key = '*', mods = 'SHIFT|SUPER', action = act.ActivateTab(7) },
          { key = '1', mods = 'SHIFT|SUPER', action = act.ActivateTab(0) },
          { key = '1', mods = 'SUPER', action = act.ActivateTab(0) },
          { key = '2', mods = 'SHIFT|SUPER', action = act.ActivateTab(1) },
          { key = '2', mods = 'SUPER', action = act.ActivateTab(1) },
          { key = '3', mods = 'SHIFT|SUPER', action = act.ActivateTab(2) },
          { key = '3', mods = 'SUPER', action = act.ActivateTab(2) },
          { key = '4', mods = 'SHIFT|SUPER', action = act.ActivateTab(3) },
          { key = '4', mods = 'SUPER', action = act.ActivateTab(3) },
          { key = '5', mods = 'SHIFT|SUPER', action = act.ActivateTab(4) },
          { key = '5', mods = 'SUPER', action = act.ActivateTab(4) },
          { key = '6', mods = 'SHIFT|SUPER', action = act.ActivateTab(5) },
          { key = '6', mods = 'SUPER', action = act.ActivateTab(5) },
          { key = '7', mods = 'SHIFT|SUPER', action = act.ActivateTab(6) },
          { key = '7', mods = 'SUPER', action = act.ActivateTab(6) },
          { key = '8', mods = 'SHIFT|SUPER', action = act.ActivateTab(7) },
          { key = '8', mods = 'SUPER', action = act.ActivateTab(7) },
          { key = '9', mods = 'SHIFT|SUPER', action = act.ActivateTab(-1) },
          { key = '9', mods = 'SUPER', action = act.ActivateTab(-1) },
          { key = '@', mods = 'SUPER', action = act.ActivateTab(1) },
          { key = '@', mods = 'SHIFT|SUPER', action = act.ActivateTab(1) },
          { key = '^', mods = 'SUPER', action = act.ActivateTab(5) },
          { key = '^', mods = 'SHIFT|SUPER', action = act.ActivateTab(5) },
          -- フォントサイズ
          { key = ')', mods = 'SUPER', action = act.ResetFontSize },
          { key = ')', mods = 'SHIFT|SUPER', action = act.ResetFontSize },
          { key = '+', mods = 'SUPER', action = act.IncreaseFontSize },
          { key = '+', mods = 'SHIFT|SUPER', action = act.IncreaseFontSize },
          { key = '-', mods = 'SUPER', action = act.DecreaseFontSize },
          { key = '-', mods = 'SHIFT|SUPER', action = act.DecreaseFontSize },
          { key = '0', mods = 'SUPER', action = act.ResetFontSize },
          { key = '0', mods = 'SHIFT|SUPER', action = act.ResetFontSize },
          { key = '=', mods = 'SUPER', action = act.IncreaseFontSize },
          { key = '=', mods = 'SHIFT|SUPER', action = act.IncreaseFontSize },
          { key = '_', mods = 'SUPER', action = act.DecreaseFontSize },
          { key = '_', mods = 'SHIFT|SUPER', action = act.DecreaseFontSize },
          -- コピー/ペースト
          { key = 'C', mods = 'SUPER', action = act.CopyTo 'Clipboard' },
          { key = 'C', mods = 'SHIFT|SUPER', action = act.CopyTo 'Clipboard' },
          { key = 'V', mods = 'SUPER', action = act.PasteFrom 'Clipboard' },
          { key = 'V', mods = 'SHIFT|SUPER', action = act.PasteFrom 'Clipboard' },
          { key = 'c', mods = 'SHIFT|SUPER', action = act.CopyTo 'Clipboard' },
          { key = 'c', mods = 'SUPER', action = act.CopyTo 'Clipboard' },
          { key = 'v', mods = 'SHIFT|SUPER', action = act.PasteFrom 'Clipboard' },
          { key = 'v', mods = 'SUPER', action = act.PasteFrom 'Clipboard' },
          { key = 'Copy', mods = 'NONE', action = act.CopyTo 'Clipboard' },
          { key = 'Paste', mods = 'NONE', action = act.PasteFrom 'Clipboard' },
          -- アプリケーション操作
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
          { key = 'T', mods = 'SUPER', action = act.SpawnTab 'CurrentPaneDomain' },
          { key = 'T', mods = 'SHIFT|SUPER', action = act.SpawnTab 'CurrentPaneDomain' },
          { key = 'U', mods = 'SUPER', action = act.CharSelect{ copy_on_select = true, copy_to =  'ClipboardAndPrimarySelection' } },
          { key = 'U', mods = 'SHIFT|SUPER', action = act.CharSelect{ copy_on_select = true, copy_to =  'ClipboardAndPrimarySelection' } },
          { key = 'W', mods = 'SUPER', action = act.CloseCurrentTab{ confirm = true } },
          { key = 'W', mods = 'SHIFT|SUPER', action = act.CloseCurrentTab{ confirm = true } },
          { key = 'X', mods = 'SUPER', action = act.ActivateCopyMode },
          { key = 'X', mods = 'SHIFT|SUPER', action = act.ActivateCopyMode },
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
          { key = 't', mods = 'SHIFT|SUPER', action = act.SpawnTab 'CurrentPaneDomain' },
          { key = 't', mods = 'SUPER', action = act.SpawnTab 'CurrentPaneDomain' },
          { key = 'u', mods = 'SHIFT|SUPER', action = act.CharSelect{ copy_on_select = true, copy_to =  'ClipboardAndPrimarySelection' } },
          { key = 'w', mods = 'SHIFT|SUPER', action = act.CloseCurrentTab{ confirm = true } },
          { key = 'w', mods = 'SUPER', action = act.CloseCurrentTab{ confirm = true } },
          { key = 'x', mods = 'SHIFT|SUPER', action = act.ActivateCopyMode },
          -- その他
          { key = 'phys:Space', mods = 'SHIFT|SUPER', action = act.QuickSelect },
          { key = 'PageUp', mods = 'SHIFT', action = act.ScrollByPage(-1) },
          { key = 'PageUp', mods = 'SHIFT|SUPER', action = act.MoveTabRelative(-1) },
          { key = 'PageDown', mods = 'SHIFT', action = act.ScrollByPage(1) },
          { key = 'PageDown', mods = 'SHIFT|SUPER', action = act.MoveTabRelative(1) },
        },

        key_tables = {
          workspace_nav = {
            { key = 'l', action = act.SwitchWorkspaceRelative(1) },
            { key = 'u', action = act.SwitchWorkspaceRelative(-1) },
            { key = 'a', action = act.ShowLauncherArgs{ flags = 'FUZZY|TABS|WORKSPACES' } },
            { key = 'e', action = act.EmitEvent 'switch-to-main-editor' },
            { key = 'r', action = act.ShowLauncherArgs{ flags = 'FUZZY|WORKSPACES' } },
            { key = 's', action = act.ShowLauncherArgs{ flags = 'FUZZY|WORKSPACES' } },
            { key = 'w', action = act.ShowLauncherArgs{ flags = 'FUZZY|TABS' } },
            { key = 'Escape', action = 'PopKeyTable' },
          },
        },
      }
    '';
  };
}
