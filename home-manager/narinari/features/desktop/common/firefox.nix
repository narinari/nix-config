{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  programs.firefox = {
    enable = false;
    package = pkgs.firefox-bin;
    profiles.narinari = {
      extensions = with inputs.firefox-addons.packages.${pkgs.system}; [
        bitwarden
        tridactyl
      ];
    };
  };

  xdg.configFile."tridactyl/tridactylrc".text = ''
    sanitise

    set hintchars arstgmneioqwfpbjluy
    set smoothscroll true
    set findcase smart

    # https://github.com/tridactyl/tridactyl/blob/1.24.0/src/lib/config.ts
    bind I mode ignore
    bind x fillcmdline_notrail
    bind j scrollline 10
    bind k scrollline -10
    bind G scrollto 100
    bind <C-t> tabnew
    bind h tabnext -1
    bind l tabnext +1

    bind ,r source
  '';
}
