{
  config,
  pkgs,
  ...
}:

let
  wrapperScript = pkgs.writeShellScript "gpg-agent-wrapper" ''
    set -Ceu

    case "''${PINENTRY_USER_DATA-}" in
    *TTY*)
      exec pinentry-curses "$@"
      ;;
    esac

    exec pinentry-qt "$@"
  '';
in
{
  programs.zsh.initContent = ''
    [[ -o interactive ]] && export GPG_TTY=$TTY
  '';

  programs.gpg = {
    enable = true;
    homedir = "${config.xdg.dataHome}/gnupg";
  };

  home.file."${config.programs.gpg.homedir}/gpg-agent.conf" = {
    enable = pkgs.stdenv.isLinux;
    text = ''
      pinentry-program ${wrapperScript}
    '';
  };
}
