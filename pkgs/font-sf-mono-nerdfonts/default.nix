{ lib, stdenvNoCC, nerd-font-patcher }:

stdenvNoCC.mkDerivation rec {
  pname = "sf-mono-nerdfonts";
  version = "18.0.0";

  src = ../font-sf-mono/sf-mono;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/fonts/sf-mono-nerd-font

    for f in *; do
    ${nerd-font-patcher}/bin/nerd-font-patcher -c --progressbars --out $out/share/fonts/sf-mono-nerd-font $f
    done

    runHook postInstall
  '';

  meta = with lib; {
    homepage = "https://developer.apple.com/fonts/";
    description =
      "This monospaced variant of San Francisco enables alignment between rows and columns of text, and is used in coding environments like Xcode.";
    license = {
      shortName = "Apple Font license";
      free = false;
      deprecated = false;
    };
    platforms = platforms.all;
  };
}
