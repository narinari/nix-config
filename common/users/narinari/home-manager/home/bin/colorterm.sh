#!/bin/bash
#
# Based almost entirely on Bryan Gilbert's solution:
# http://bryangilbert.com/post/etc/term/dynamic-ssh-terminal-background-colors/
#
# Sets terminal screen to color based on keywords or hex code (no #, for some reason that breaks)
#
# For SSH magic, add following to ~/.zshrc:
#
: <<'END_COMMENT'

color-ssh() {
	trap "$HOME/bin/./colorterm.sh" INT EXIT
    if [[ "$*" =~ "prod" ]]; then
        $HOME/bin/./colorterm.sh prod
    elif [[ "$*" =~ "dev" ]]; then
        $HOME/bin/./colorterm.sh dev
    else
        $HOME/bin/./colorterm.sh other
    fi
    echo "$*"
    'ssh' "$*"
}

compdef _ssh color-ssh=ssh
alias ssh=color-ssh

END_COMMENT


if [[ -n "$TMUX" ]]; then
  if [ ! -z `expr match "$1" '\([A-Fa-f0-9]\{6\}\|#[A-Fa-f0-9]\{3\}\)'` ]; then
  	tmux select-pane -P "bg=#$1"
  elif [ "$1" == "prod" ]; then
    tmux select-pane -P 'bg=#331C1F'
  elif [ "$1" == "dev" ]; then
    tmux select-pane -P 'bg=#192436'
  elif [ "$1" == "other" ]; then
    tmux select-pane -P 'bg=#253320'
  else
    tmux select-pane -P 'bg=#101010'
  fi;
else
  if [ ! -z `expr match "$1" '\([A-Fa-f0-9]\{6\}\|#[A-Fa-f0-9]\{3\}\)'` ]; then
  	printf "\033]11;#$1\007"
  elif [ "$1" == "prod" ]; then
    printf '\033]11;#331C1F\007'
  elif [ "$1" == "dev" ]; then
    printf '\033]11;#192436\007'
  elif [ "$1" == "other" ]; then
    printf '\033]11;#253320\007'
  else
    printf '\033]11;#101010\007'
  fi
fi

exit 0
