run_alpha() {
  d=~/dev/src/github.com/C-FO/CFO-Alpha
  tmux new-window -n cfo-alpha -c $d \; \
    split-window -h -c $d \; \
    set-option history-limit 5000 \; \
    send-keys "AWS_PROFILE=$AWS_PROFILE USER=narinari bin/rails s -b 0" C-m \; \
    split-window -v -c $d \; \
    send-keys 'npm install && npm run watch' C-m \; \
    split-window -v -c $d \; \
    send-keys "AWS_PROFILE=$AWS_PROFILE USER=narinari bin/rails r Tasks::RemoteCmdRunner.execute" C-m \; \
    split-window -v -c $d \; \
    send-keys "AWS_PROFILE=$AWS_PROFILE USER=narinari QUEUE=* bin/rake resque:work" C-m \; \
    split-window -v -c $d \; \
    select-pane -t:.1 \; \
    select-layout main-vertical
}
