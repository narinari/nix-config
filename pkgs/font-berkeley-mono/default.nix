{ lib, stdenvNoCC }:

stdenvNoCC.mkDerivation rec {
  pname = "berkeley-mono";
  version = "1.0.9";

  src = ./berkeley-mono;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/fonts/berkeley-mono
    cp * $out/share/fonts/berkeley-mono

    runHook postInstall
  '';

  meta = with lib; {
    homepage = "https://berkeleygraphics.com/typefaces/berkeley-mono/";
    description =
      "Berkeley Mono is a love letter to the golden era of computing.";
    license = {
      shortName = "Berkeley Graphics Developer license";
      url =
        "https://cdn.berkeleygraphics.com/static/legal/licenses/developer-license.pdf";
      free = false;
      deprecated = false;
    };
    platforms = platforms.all;
  };
}
