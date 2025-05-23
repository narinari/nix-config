{ config, ... }:

{
  programs.zsh.initContent = ''
    [[ -o interactive ]] && export GPG_TTY=$TTY
  '';

  programs.gpg = {
    enable = true;
    homedir = "${config.xdg.dataHome}/gnupg";
  };
}
