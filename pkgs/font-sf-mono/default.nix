{ lib, stdenvNoCC }:

stdenvNoCC.mkDerivation rec {
  pname = "sf-mono";
  version = "18.0.0";

  src = ./sf-mono;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/fonts/sf-mono
    cp * $out/share/fonts/sf-mono

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
