{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "lsec2";
  version = "0.2.11";

  src = fetchFromGitHub {
    owner = "goldeneggg";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-efO3i+NsQzbXVkY6xP0wzBGKIZxPveFQCM/1zYqSp00=";
  };

  vendorHash = "sha256-26FirSPK1f5BMYJtZMQo7qw5cJWXzaOhv9myNaKzHxo=";

  meta = with lib; {
    description = "List view of AWS EC2 instances.";
    homepage = "https://github.com/goldeneggg/lsec2/";
    license = licenses.mit;
  };
}
