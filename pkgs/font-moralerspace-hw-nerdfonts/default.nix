{ lib, stdenvNoCC, fetchzip }:

stdenvNoCC.mkDerivation rec {
  pname = "moralerspace-HW-nerdfonts";
  version = "0.0.11";

  src = fetchzip {
    url =
      "https://github.com/yuru7/moralerspace/releases/download/v${version}/MoralerspaceHWNF_v${version}.zip";
    hash = "sha256-w5BMoVEWsCd3teX3w556H7rNC+nh1sg/P4y8ZlL/bPA=";
  };

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/fonts
    cp -r * $out/share/fonts

    runHook postInstall
  '';

  meta = with lib; {
    homepage = "https://github.com/yuru7/moralerspace/";
    description =
      "Moralerspace は、欧文フォント Monaspace と日本語フォント IBM Plex Sans JP などを合成したプログラミング向けフォントです。";
    license = licenses.ofl;
    platforms = platforms.all;
  };
}
