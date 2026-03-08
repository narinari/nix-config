{
  lib,
  stdenv,
  fetchFromGitHub,
  kernel,
  kmod,
}:

stdenv.mkDerivation rec {
  pname = "px4_drv";
  version = "0.5.5";

  src = fetchFromGitHub {
    owner = "humuu135";
    repo = "px4_drv";
    rev = "496a9a7ac53a866b117d45c0844777c68b7b99c7";
    sha256 = "sha256-1jkqLjVLKA+NHyp0dVXd7xLEp2CmhdlWAdPFp+fWwdk=";
  };

  sourceRoot = "${src.name}/driver";

  nativeBuildInputs = [ kmod ] ++ kernel.moduleBuildDependencies;

  makeFlags = [
    "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "KVER=${kernel.modDirVersion}"
  ];

  ARCH = stdenv.hostPlatform.linuxArch;

  preBuild = ''
    cat > revision.h << 'EOF'
    // revision.h

    #ifndef __REVISION_H__
    #define __REVISION_H__

    #define REVISION_NUMBER	"${version}"
    #define REVISION_NAME	"master"
    #define COMMIT_HASH	"7fa9f05d2cbdf1d821f479248d561f9868051b8b"

    #endif
    EOF
  '';

  installPhase = ''
    runHook preInstall

    install -D px4_drv.ko $out/lib/modules/${kernel.modDirVersion}/misc/px4_drv.ko
    install -D -m 644 ../etc/99-px4video.rules $out/lib/udev/rules.d/99-px4video.rules

    runHook postInstall
  '';

  meta = with lib; {
    description = "Unofficial Linux driver for PLEX PX4/PX5/PX-MLT series ISDB-T/S receivers";
    homepage = "https://github.com/nns779/px4_drv";
    license = licenses.gpl2Only;
    platforms = platforms.linux;
  };
}
