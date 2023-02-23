#!/usr/bin/env zsh

set -u

autoload -Uz colors
colors

source ~/.zsh/plugins/aws.zsh

instance=$1

start_instance $instance
if [ $? -ne 0 ]; then
    read -p "${fg[red]}Press [Enter] key to resume.${reset_color}"
    return -1
fi

exec ssh -tt -q $instance tmux "new-session -A -D -s main"
