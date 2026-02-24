{ _, ... }:

{
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap"; # Remove unlisted casks/brews
    };

    taps = [
      "goldeneggg/lsec2"
      "koekeishiya/formulae"
    ];

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
      "wezterm"
      "keycastr"
      "the-unarchiver"
      "xquartz"
      "bestres"
      "licecap"
      "contexts"
    ];
  };
}
