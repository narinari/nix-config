{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  unzip,
}:

stdenv.mkDerivation rec {
  pname = "it930x-firmware";
  version = "1";

  # fwtoolのソース
  px4_drv_src = fetchFromGitHub {
    owner = "nns779";
    repo = "px4_drv";
    rev = "7fa9f05d2cbdf1d821f479248d561f9868051b8b";
    sha256 = "sha256-iGzMNpIkoyjptMHw2uAxF7+KjC3LQVFwrsoiA7Wbq+E=";
  };

  # PLEX公式ドライバ（ファームウェア抽出元）
  plexDriver = fetchurl {
    url = "http://plex-net.co.jp/plex/pxw3u4/pxw3u4_BDA_ver1x64.zip";
    sha256 = "sha256-vfO064S2nMustLo98vWck8gD720/YeepClMcIsMBogA=";
  };

  nativeBuildInputs = [ unzip ];

  dontUnpack = true;

  buildPhase = ''
    # fwtoolをビルド
    cp -r ${px4_drv_src}/fwtool .
    chmod -R +w fwtool
    cd fwtool
    make

    # PLEXドライバからPXW3U4.sysを抽出
    unzip -oj ${plexDriver} "pxw3u4_BDA_ver1x64/PXW3U4.sys" -d .

    # ファームウェアを抽出
    ./fwtool PXW3U4.sys it930x-firmware.bin
  '';

  installPhase = ''
    runHook preInstall

    install -D -m 644 it930x-firmware.bin $out/lib/firmware/it930x-firmware.bin

    runHook postInstall
  '';

  meta = with lib; {
    description = "IT930x firmware for PLEX PX4 tuners";
    homepage = "https://github.com/nns779/px4_drv";
    license = licenses.unfreeRedistributableFirmware;
    platforms = platforms.linux;
  };
}
