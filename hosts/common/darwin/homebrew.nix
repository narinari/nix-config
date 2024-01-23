{ _, ... }:

{
  homebrew = {
    onActivation = {
      enable = true;
      autoUpdate = true;
    };

    taps = [ "goldeneggg/lsec2" "koekeishiya/formulae" ];

    brews = [
      "automake"
      "coreutils"
      "asdf"
      "mecab"
      "yadm"
      "goldeneggg/lsec2/lsec2"
      # {
      #   name = "koekeishiya/formulae/skhd";
      #   start_service = true;
      #   restart_service = "changed";
      # }
      # {
      #   name = "koekeishiya/formulae/yabai";
      #   start_service = true;
      #   restart_service = "changed";
      # }
    ];

    casks = [
      "keycastr"
      "the-unarchiver"
      "aquaskk"
      "xquartz"
      "bestres"
      "google-chrome"
      "licecap"
      "contexts"
      "firefox"
      "skitch"
    ];
  };
}
