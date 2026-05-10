{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  zlib,
  openssl,
}:
let
  version = "0.1.2";
  sources = {
    "x86_64-linux" = {
      url = "https://github.com/h4ckf0r0day/obscura/releases/download/v${version}/obscura-x86_64-linux.tar.gz";
      hash = "sha256-MHzliv/qP/OSI79XPPORyIg+CBHTbpzXGF+MfFSUKAI=";
    };
    "aarch64-linux" = {
      url = "https://github.com/h4ckf0r0day/obscura/releases/download/v${version}/obscura-aarch64-linux.tar.gz";
      hash = lib.fakeHash;
    };
    "x86_64-darwin" = {
      url = "https://github.com/h4ckf0r0day/obscura/releases/download/v${version}/obscura-x86_64-macos.tar.gz";
      hash = lib.fakeHash;
    };
    "aarch64-darwin" = {
      url = "https://github.com/h4ckf0r0day/obscura/releases/download/v${version}/obscura-aarch64-macos.tar.gz";
      hash = lib.fakeHash;
    };
  };
  src =
    sources.${stdenv.hostPlatform.system}
      or (throw "obscura: unsupported platform ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "obscura";
  inherit version;

  src = fetchurl src;

  sourceRoot = ".";

  nativeBuildInputs = lib.optionals stdenv.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.isLinux [
    stdenv.cc.cc.lib
    zlib
    openssl
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 obscura        "$out/bin/obscura"
    install -Dm755 obscura-worker "$out/bin/obscura-worker"
    runHook postInstall
  '';

  passthru.version = version;

  meta = with lib; {
    description = "Lightweight Rust headless browser with CDP server";
    homepage = "https://github.com/h4ckf0r0day/obscura";
    license = licenses.mit;
    mainProgram = "obscura";
    platforms = lib.attrNames sources;
  };
}
