{ lib, stdenvNoCC, nerd-font-patcher }:

stdenvNoCC.mkDerivation rec {
  pname = "berkeley-mono-nerdfonts";
  version = "1.0.9";

  src = ../font-berkeley-mono/berkeley-mono;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/fonts/berkeley-mono-nerd-font

    for f in *; do
    ${nerd-font-patcher}/bin/nerd-font-patcher -c --progressbars --out $out/share/fonts/berkeley-mono-nerd-font $f
    done

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
