{ fetchzip, lib, stdenvNoCC }:

stdenvNoCC.mkDerivation rec {
  pname = "ibm-plex-sans";
  version = "6.3.0";

  src = fetchzip {
    url = "https://github.com/IBM/plex/releases/download/v6.3.0/OpenType.zip";
    hash = "sha256-RvD/aeZrvltJiuAHqYMNaRsjLgTdcC1/5zqlcd4qKAA=";
  };

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/fonts
    cp -r * $out/share/fonts

    runHook postInstall
  '';

  meta = with lib; {
    homepage = "https://www.ibm.com/plex/";
    description =
      "Meet the IBM Plex® typeface, our corporate typeface family. It’s global, it’s versatile and it’s distinctly IBM.";
    license = licenses.ofl;
    platforms = platforms.all;
  };
}
