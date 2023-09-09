autoload -Uz colors
colors

alias saml2aws='ONELOGIN_MFA_IP_ADDRESS=$(curl -SsL checkip.amazonaws.com) saml2aws'

switch_profile() {
  local profile=$({grep '\[profile .\+\]' ~/.aws/config | sed -e 's/\[profile //' -e 's/\].*$//'; grep '^\[.\+\]$' ~/.aws/credentials | sed -e 's/^\[//' -e 's/\]$//'}| sort -u | fzf)
  export AWS_PROFILE="$profile"
  echo update environment AWS_PROFILE=$AWS_PROFILE
}

list_roles() {
  local roles_list=${XDG_DATA_HOME:-$HOME/.local/share}/aws_roles_list
  local dev_pattern=/507110214534:role\\/freee-sso-developer/
  local script=$(<<-AWK
    BEGIN { print "ACCOUNT", "ROLE", "TAGS", "GEN_AT:" date }
    /Account:/ { acc=\$0; sub(/.*Account: /, "", acc); gsub(/ /, "", acc) }
    /arn/ { if (\$1 ~ ${dev_pattern}) { tags="dev" } else { tags="" }; print acc, \$1, tags }
AWK
)

  saml2aws list-roles --skip-prompt | awk -v date="$(date "+%Y-%m-%dT%H:%M:%S%z")" "$script" | tee $roles_list
}

switch_role() {
  local roles_list=${XDG_DATA_HOME:-$HOME/.local/share}/aws_roles_list
  if [ ! -e $roles_list ]; then
    list_roles
    if [ $? -ne 0 ]; then
      echo "${fg[red]}cancel!!${reset_color}"
      return 1
    fi
  fi

  local line=$(cat $roles_list | column -s \  -t | fzf-tmux --header-lines=1)
  # echo $line
  [ -z "$line" ] && {
    echo "${fg[red]}cancel!!${reset_color}"
    return
  }

  : ${(A)selected::=${(@s: :)line}}
  local account="$selected[1]"
  local role="$selected[2]"
  local tags="$selected[3]"
  local profile="$selected[1]:${selected[2]#*role/}"

  # echo "role=$role profile=$profile"

  local token_expires=$(aws configure get x_security_token_expires --profile $profile|sed 's/+09:00/+0900/')
  [ -z "$token_expires" ] && {
    awslogin $role $profile $tags
    return
  }

  local ex=$(date -j -f '%Y-%m-%dT%H:%M:%S%z' $token_expires '+%s')
  [[ $(( ex - $(date '+%s') )) -le 60 ]] && {
    echo "${fg[red]}Token has expired or will soon. Expires: $token_expires${reset_color}"
    awslogin $role $profile $tags
    return
  }

  echo "${fg[green]}Token alive until $token_expires${reset_color}"
  export AWS_PROFILE="$profile"
}

awslogin() {
  if [[ "$3" =~ dev ]]; then
    local opts="--session-duration=43200" # 12 hours of sec
  fi

  saml2aws login --skip-prompt --force $opts --role $1 -p $2 && \
  export AWS_PROFILE="$profile"
}

onelogin() {
  interactive=0
  if [[ "$1" == '-i' ]]; then
    interactive=1
    shift
  fi

  if [[ interactive -eq 1 ]]; then
    saml2aws login --skip-prompt --force $@
    if [ $? -ne 0 ]; then
      return 1
    fi
    export AWS_PROFILE=saml
  else
    saml2aws login -a dev --skip-prompt --force $@
    if [ $? -ne 0 ]; then
      return 1
    fi
    export AWS_PROFILE=dev
  fi
}

alias sp=switch_profile
alias sr=switch_role
alias o=onelogin

eval "$(saml2aws --completion-script-zsh)"

go_dev() {
  if [[ -n $TMUX ]]; {
tmux display AWS_PROFILE=freee-development\(507110214534\):freee-sso-developer
tmux setenv AWS_PROFILE freee-development\(507110214534\):freee-sso-developer \; setenv AWS_REGION ap-northeast-1 \; new-window -n " narinari-dev" connect-remote-env.zsh i-086e2a1f159186c16
  }
}

bg_color() {
  case "$1" in
    "prod") echo "331C1F";;
    "stg") echo "192436";;
    "other") echo "253320";;
    *) echo "101010"
  esac
}

progress() {
  while :
  do
    echo -n .
    sleep 1
  done
}

wait_process() {
  progress &
  pj=$!
  wait $1
  kill $pj
}

start_instance() {
  i=$1
  shift

  s=$(aws ec2 describe-instance-status --instance-id $i --query 'InstanceStatuses[*].InstanceState.Name|[0]' --output text)
  if [ "$s" = "running" ]; then
    echo "${fg[green]} already running $i ${reset_color}"
    return 0
  fi

  echo start instance $i

  aws ec2 start-instances --instance-ids $i > /dev/null &
  wait_process $!
  if [ $? != 0 ]; then
    echo "${fg[red]} can not start $i ${reset_color}"
    return 1
  fi

  aws ec2 wait instance-running --instance-ids $i &
  wait_process $!

  aws ec2 wait instance-status-ok --instance-ids $i &
  wait_process $!
}

function eks-step() {
  local cluster_name=$(aws eks list-clusters | jq -r '.clusters[]' | sort | fzf-tmux --prompt="select target cluster ")
  echo "cluster_name=$cluster_name"

  local environment="default"
  case "$cluster_name" in
    "production"*) environment="prod";;
    "staging"*) environment="stg";;
    "integration"*) environment="other";;
  esac
  echo "environment=$environment"

  local token=""
  local alllist=""

  while true; do
    local json=$(aws ssm describe-instance-information --max-items 50 --filters "Key=tag:alpha.eksctl.io/cluster-name,Values=$cluster_name" --starting-token "$token")
    local token=$(echo $json | jq -r '.NextToken')

    local list=$(echo $json | jq -r '.InstanceInformationList[] | [.InstanceId, .IPAddress, .PingStatus, .LastPingDateTime, .ComputerName] | @csv' | sed 's/"//g')
    local alllist=$(echo -e "${alllist}\n${list}")

    if [ -z "$token" -o "$token" = "null" ]; then
      break
    fi
  done

  local inst=$(echo -e "$alllist" | grep ssm-agent-r2 | column -t -s, | fzf-tmux)
  local id=$(echo $inst | awk '{print $1}')

  BUFFER="AWS_PROFILE=$AWS_PROFILE ONELOGIN_USERNAME=\"narinari@c-fo.com\" ssh $id"
  if [[ ! -z $TMUX ]]; then
    BUFFER="tmux new-window -n \" ${environment} ${id}\" '$BUFFER'"
  fi
  zle redisplay
}

zle -N eks-step
