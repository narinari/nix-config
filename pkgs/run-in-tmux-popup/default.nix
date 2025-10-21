{
  lib,
  buildGoLatestModule,
  fetchFromGitHub,
  pkgs,
}:

buildGoLatestModule rec {
  pname = "run-in-tmux-popup";
  version = "0.1.0";

  src = builtins.fetchGit {
    url = "https://github.com/ngicks/run-in-tmux-popup.git";
    ref = "main";
    rev = "1d60f29f6776fa49b9043d68530deec54c811b9c";
  };
  vendorHash = null;

  meta = with lib; {
    description = "Wrappers to call things in tmux popup.";
    homepage = "https://github.com/ngicks/run-in-tmux-popup";
    license = licenses.mit;
  };
}
