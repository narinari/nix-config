{
  config,
  pkgs,
  outputs,
  ...
}:

let
  run-in-tmux-popup-pkg = outputs.packages."${pkgs.system}".run-in-tmux-popup;
  wrapperScript = pkgs.writeShellScript "gpg-agent-wrapper" ''
    set -Ceu

    case "''${PINENTRY_USER_DATA-}" in
    *TTY*)
      exec pinentry-curses "$@"
      ;;
    *TMUX_POPUP*)
      exec ${run-in-tmux-popup-pkg}/bin/tmux-popup-pinentry-curses "$@"
      ;;
    esac

    exec pinentry-qt "$@"
  '';
in
{
  programs.zsh.initContent = ''
    [[ -o interactive ]] && export GPG_TTY=$TTY
    if [ -n "''${TMUX}" ]; then
      export PINENTRY_USER_DATA="TMUX_POPUP:$(which tmux):''${TMUX}"
    elif [ -n "''${ZELLIJ}" ]; then
      export PINENTRY_USER_DATA="ZELLIJ_POPUP:$(which zellij):''${ZELLIJ_SESSION_NAME}"
    fi
  '';

  programs.gpg = {
    enable = true;
    homedir = "${config.xdg.dataHome}/gnupg";
  };

  home.file."${config.programs.gpg.homedir}/gpg-agent.conf".text = ''
    pinentry-program ${wrapperScript}
  '';
}
