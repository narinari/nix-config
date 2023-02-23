run_ocean() {
    d=~/dev/src/github.com/C-FO/ocean
    tmux new-window -n ocean -c $d \; \
        split-window -h -c $d \; \
        select-pane -t:.1 \; \
        send-keys "AWS_PROFILE=$AWS_PROFILE USER=narinari bin/rpc server" C-m \; \
        split-window -v -c $d \; \
        send-keys "AWS_PROFILE=$AWS_PROFILE USER=narinari bin/commander server" C-m \; \
        split-window -v -c $d \; \
        set-option history-limit 5000 \; \
        send-keys "AWS_PROFILE=$AWS_PROFILE USER=narinari bin/aggregator grpc" C-m \; \
        select-pane -t:.{right}
}
