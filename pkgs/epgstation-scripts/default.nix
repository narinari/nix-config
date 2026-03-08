{ stdenv, nodejs }:

stdenv.mkDerivation {
  name = "epgstation-scripts";
  src = ./.;
}
