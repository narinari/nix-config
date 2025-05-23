{
  config,
  pkgs,
  lib,
  ...
}:

{
  xdg.configFile."lf/icons".source = ./lf/icons;

  programs.lf = {
    enable = true;
    commands =
      {
        editor-open = "$$EDITOR $f";
        mkdir = ''
          ''${{
            printf "Directory Name: "
            read DIR
            mkdir $DIR
          }}
        '';
      }
      // lib.optionalAttrs pkgs.stdenv.isLinux {
        dragon-out = ''%${pkgs.xdragon}/bin/xdragon -a -x "$fx"'';
      };
    keybindings = {

      "\\\"" = "";
      o = "";
      c = "mkdir";
      "." = "set hidden!";
      "`" = "mark-load";
      "\\'" = "mark-load";
      "<enter>" = "open";

      do = "dragon-out";

      "g~" = "cd";
      gh = "cd";
      "g/" = "/";

      ee = "editor-open";
      V = ''$''${pkgs.bat}/bin/bat --paging=always --theme=gruvbox "$f"'';

      # ...
    };

    settings = {
      preview = true;
      hidden = true;
      drawbox = true;
      icons = true;
      ignorecase = true;
    };
  };
}
