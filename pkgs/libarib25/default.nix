{
  stdenv,
  fetchFromGitHub,
  cmake,
  clang,
  pcsclite,
}:

stdenv.mkDerivation {
  name = "libarib25";
  version = "1";

  nativeBuildInputs = [
    cmake
    clang
  ];
  buildInputs = [ pcsclite ];

  cmakeFlags = [
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
  ];

  src = fetchFromGitHub {
    owner = "stz2012";
    repo = "libarib25";
    rev = "ab6afa7c7f4022af7dda7976489ec7a0716efb9a";
    sha256 = "1jj4qh75rf0awydswrmfsdp3f4vkniyzmwks48ahy0mjvk6y182m";
  };
}
