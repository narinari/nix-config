{ lib, fetchFromGitHub, buildNpmPackage }:
let
  pname = "fosi";
  version = "1.5.3";
in buildNpmPackage rec {
  inherit pname version;

  src = fetchFromGitHub {
    owner = "hotoku";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-Hch3WvsR+uIGHPfqOuYytcXbk17Har3ERua7bZt6pvU=";
  };

  npmDepsHash = "sha256-joIfbUqs0u2KV9M8IS5HtN1XJugquzoJXNwi1pVL+uo=";
  makeCacheWritable = true;

  meta = with lib; {
    description = "livereloading server for markdown editing";
    homepage = "https://github.com/hotoku/fosi/";
    license = licenses.mit;
  };
}
