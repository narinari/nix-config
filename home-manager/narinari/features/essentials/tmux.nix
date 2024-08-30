{ pkgs, ... }: {

  home.packages = with pkgs; [ (lib.mkIf stdenv.isLinux sysstat) ];

  programs.tmux = {
    enable = true;
    prefix = "C-q";
    keyMode = "vi";
    aggressiveResize = true;
    clock24 = true;
    escapeTime = 1;
    baseIndex = 1;
    # newSession = true;
    plugins = with pkgs.tmuxPlugins; [
      copycat
      copy-toolkit
      extrakto
      # nord
      # gruvbox
      {
        plugin = tokyo-night-tmux;
        extraConfig = ''
          set -g @tokyo-night-tmux_show_datetime 0
          set -g @tokyo-night-tmux_show_git 0
          set -g @tokyo-night-tmux_show_path 1
          set -g @tokyo-night-tmux_path_format relative
          set -g @tokyo-night-tmux_window_id_style dsquare
        '';
      }
      cpu
      prefix-highlight
      yank
      tmux-thumbs
      tmux-fzf
      {
        plugin = resurrect;
        extraConfig = ''
          ## Restore Panes
          set -g @resurrect-capture-pane-contents 'on'
        '';
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-boot 'on'

          ## Restore last saved environment (automatically)
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '60' # minutes
        '';
      }
    ];
    secureSocket = false;
    terminal = "tmux-256color";
    historyLimit = 30000;
    extraConfig = ''
      #new-session -A -D -s main

      # C-bのキーバインドを解除する
      unbind C-b

      # destroy the last shell in a session, it switches to another active session
      set -g detach-on-destroy off

      # ペインの番号表示時間（ミリ秒）
      setw -g display-panes-time 3000

      # 設定ファイルをリロードする
      bind r source-file ~/.config/tmux/tmux.conf \; display-message "Config reloaded..."

      # | でペインを縦に分割する
      bind | split-window -h

      # - でペインを横に分割する
      bind - split-window -v

      # Vimのキーバインドでペインを移動する
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R
      bind -r C-h select-window -t :-
      bind -n C-Tab next-window
      bind -r C-l select-window -t :+
      bind -n C-S-Tab previous-window

      # Vimのキーバインドでペインをリサイズする
      bind -r H resize-pane -L 5
      bind -r J resize-pane -D 5
      bind -r K resize-pane -U 5
      bind -r L resize-pane -R 5

      bind -n M-e switch-client -Ttable1
      bind -T table1 a choose-tree
      bind -T table1 e switch-client -t main \; select-window -t editor
      bind -T table1 l switch-client -t main \; select-window -t editor \; send-keys Space l
      bind -T table1 p run -b open-project-fzf
      bind -T table1 r choose-session
      bind -T table1 s run -b tmux-session-fzf
      bind -T table1 w choose-tree -w

      # session の作成, 移動
      bind -n M-S-C new-session
      bind -n M-l switch-client -n
      bind -n M-u switch-client -p

      bind e setw synchronize-panes\; display-message "synchronize-panes #{?pane_synchronized,on,off}"

      # https://waylonwalker.com/tmux-fzf-session-jump/
      bind C-j display-popup -E "\
          tmux list-sessions -F '#{?session_attached,,#{session_name}}' |\
          sed '/^$/d' |\
          fzf --reverse --header jump-to-session --preview 'tmux capture-pane -pt {}'  |\
          xargs tmux switch-client -t"

      # send the prefix to client inside window
      bind -T root F12  \
        set prefix None \;\
        set key-table off \;\
        if -F '#{pane_in_mode}' 'send-keys -X cancel' \;\
        set -g status off \;\
        refresh-client -S

      bind -T off F12 \
        set -u prefix \;\
        set -u key-table \;\
        set -u status-style \;\
        set -u window-status-current-style \;\
        set -u window-status-current-format \;\
        set -g status on \;\
        refresh-client -S

      # launch
      bind g run -b 'zsh -c "go_dev"'
      bind m popup ~/bin/menu-fzf.zsh
      bind G command-prompt -p hostname 'new-window -n " %1" ssh -tt -q %1 tmux "new-session -A -D -s main"'

      set -g mouse on

      # アタッチしたときに仮想端末が変わってるかもしれないので更新する
      set -ag update-environment \
        "DISPLAY\
        SSH_ASKPASS\
        SSH_AUTH_SOCK\
        SSH_AGENT_PID\
        SSH_CONNECTION\
        SSH_TTY\
        WINDOWID\
        XAUTHORITY"

      # TrueColor
      set -ga terminal-overrides ",*:Tc"

      ## ヴィジュアルノーティフィケーションを有効にする
      setw -g monitor-activity on
      set -g visual-activity on
      ## ステータスバーを上部に表示する
      set -g status-position top

      set -g set-clipboard on

      set-hook -g after-new-window 'if -F "#{m: prod *,#{window_name}}" "set window-style bg=#331C1F"'
      set-hook -g after-new-window 'if -F "#{m: stg *,#{window_name}}" "set window-style bg=#192436"'
      set-hook -g after-new-window 'if -F "#{m: other *,#{window_name}}" "set window-style bg=#253320"'

      # startup script
      ## mainセッションの最初のウィンドウ名を `editor` にする
      # %if #{session_created}
        %if #{==:#{session_name},main}
          rename-window -t main:1 editor
        %endif
      # %endif
    '';
  };
}
