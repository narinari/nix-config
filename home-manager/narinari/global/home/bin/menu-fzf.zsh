#!/usr/bin/env zsh

[[ -e ~/.zsh/plugins/fzf.zsh ]] && . ~/.zsh/plugins/fzf.zsh

menu=$(\ls ~/bin/*-fzf|grep -v menu-fzf.zsh)

selected=$(echo $menu|fzf-tmux)

exec $selected
