{
  stdenv,
  fetchFromGitHub,
  automake,
  autoconf,
  pcsclite,
  libarib25,
}:

stdenv.mkDerivation {
  name = "recpt1";

  buildInputs = [
    autoconf
    automake
    pcsclite
    libarib25
  ];

  src = fetchFromGitHub {
    owner = "stz2012";
    repo = "recpt1";
    rev = "5b69eb8b988276c0570b91821b29183edd3cc7e4";
    sha256 = "1sxjgc3dngq4q5cjq9gwl2qfchczxymqp51sw0gjacn8j04c0lbs";
  };

  configureFlags = [ "--enable-b25" ];

  preConfigure = ''
    cd recpt1
    ./autogen.sh
  '';

  postBuild = ''
    mkdir -p $out/bin
  '';
}
