{ config, pkgs, ... }:

let lessStateDir = "${config.xdg.stateHome}/less";
in {
  home = {
    packages = [ pkgs.less ];

    sessionVariables = { LESSHISTFILE = "${lessStateDir}/history"; };

    file."${lessStateDir}/.keep" = {
      recursive = true;
      text = "";
    };
  };
}
