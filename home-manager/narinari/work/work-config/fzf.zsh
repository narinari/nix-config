export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git"'
export FZF_DEFAULT_OPTS='--height 40% --reverse --border --inline-info'
export FZF_TMUX=1
export FZF_TMUX_OPTS='-p 80%'

[ -e /usr/share/doc/fzf/examples/completion.zsh ] && . /usr/share/doc/fzf/examples/completion.zsh
[ -e /usr/share/doc/fzf/examples/key-bindings.zsh ] && . /usr/share/doc/fzf/examples/key-bindings.zsh
[ -e /usr/share/fzf/completion.zsh ] && . /usr/share/fzf/completion.zsh
[ -e /usr/share/fzf/key-bindings.zsh ] && . /usr/share/fzf/key-bindings.zsh
[ -e /usr/local/opt/fzf/shell/completion.zsh ] && . /usr/local/opt/fzf/shell/completion.zsh
[ -e /usr/local/opt/fzf/shell/key-bindings.zsh ] && . /usr/local/opt/fzf/shell/key-bindings.zsh

which fzf-tmux > /dev/null && {
  alias fzf=fzf-tmux
  export FZF_TMUX=1
  export FZF_TMUX_OPTS='-p 80%'
}

function fzf-ec2-host-select-tmux () {
    stage=$(cat <<- LIST
		production
		staging
		oboro
		midori
		hibiki
		laphroaig
		ardbeg
	LIST
    )
    # host=$(grep -E "^Host" ~/.ssh/config|sed -e '/\*/d' -e 's/Host //' |sort)
    stage=$(echo $stage $host| fzf-tmux --prompt="Stage: ")
    if [[ -n "$stage" ]]; then
        # if (( ${host[(I)$stage]} )); then
        #     ssh-build $stage $stage
        #     return 0
        # fi

        filter="Stage=$stage"
    fi
    selected=$(lsec2 --region ap-northeast-1 -c $filter|fzf-tmux --prompt="Host: ")
    # : ${(A)selected::=${(@s:	:)${1}}}
    : ${(A)=selected::=${(@)selected}}
    typeset -A meta
    echo ${selected[6]} | IFS="=," read -A meta
    iname=${selected[1]}
    ip=${selected[2]}
    name=${meta[Name]}
    safe_name="${meta[Project]}_${meta[Stage]}_${meta[Role]}"

    fzf-ec2-select-actions ${name:-$safe_name} $iname $ip ${selected[5]}
    #echo $BUFFER
}

function ssh-build () {
    name=$1
    hostname=$2

    if [[ -z $TMUX ]]; then
        BUFFER="ssh -tt -q ${hostname} tmux 'new-session -A -D -s \" ${name}\"'"
    else
        BUFFER="tmux new-window -n \" ${name}\" ssh -tt -q ${hostname} tmux 'new-session -A -D -s \" ${name}\"'"
    fi
}

function fzf-ec2-select-actions () {
    name=$1
    iname=$2
    hostname=$3
    state=$4

    actions=$(cat <<- LIST
		ssh
		start-instance
	LIST
    )
    # action=$(echo $actions| fzf-tmux --prompt="Action: ")

    case "$state" in
        "running") action=ssh;;
        "stopped") action=start-instance;;
        *) echo "action not support for $state"
           return 1
    esac

    case "$action" in
         "ssh" ) ssh-build $name $hostname;;
         "start-instance") BUFFER="start_instance $iname";;
         *) echo abort
    esac
}

function fzf-ec2-host-select-tmux-widget () {
    fzf-ec2-host-select-tmux
    zle accept-line
}

zle -N fzf-ec2-host-select-tmux-widget

function fzf-ghq-list {
    local ghq_list="$(ghq list)"

    selected=$(echo $ghq_list | fzf-tmux)
    [[ -z $selected ]] && return

    action=$(echo "open\nselect" | fzf-tmux)
    [[ -z $action ]] && return

    case $action in
        "open") open-project $selected;;
        "select")
            echo "cd $(ghq root)/$selected"
        BUFFER="cd $(ghq root)/$selected";;
        *) return;;
    esac
    zle accept-line
}

zle -N fzf-ghq-list


# fzf-cdr
alias cdd='fzf-cdr'
function fzf-cdr() {
    target_dir=$(cdr -l | sed 's/^[^ ][^ ]*  *//' | fzf)
    target_dir=$(echo ${target_dir/\~/$HOME})
    [[ -z $target_dir ]] && return

    cd $target_dir
}


function fzf-git-branches {
    git checkout $(git branch -a | tr -d " " |fzf --height 100% --prompt "CHECKOUT BRANCH>" --preview "git log --color=always {}" | head -n 1 | sed -e "s/^\*\s*//g" -e "s/remotes\/origin\///g")
}

zle -N fzf-git-branches
