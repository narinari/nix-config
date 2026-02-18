{
  pkgs,
  lib,
  outputs,
  inputs,
  ...
}:

# nix.nixPath based on the logic from `flake-utils-plus`
# https://github.com/gytis-ivaskevicius/flake-utils-plus/blob/v1.3.0/lib/options.nix
let
  inherit (builtins) map;
  inherit (lib) mkForce filterAttrs mapAttrsToList;
  inherit (lib.trivial) pipe;

  hasOutputs = _: flake: flake ? outputs;
  hasPackages = _: flake: flake.outputs ? legacyPackages || flake.outputs ? packages;

  flakesWithPkgs = pipe inputs (
    map filterAttrs [
      hasOutputs
      hasPackages
    ]
  );
  nixPath = mapAttrsToList (name: _: "${name}=/etc/nix/inputs/${name}") flakesWithPkgs;
in
{
  imports = [
    inputs.home-manager.darwinModules.home-manager
    ./copy-applications.nix
    ./diff-closures.nix
    ./fonts.nix
    ./keyboad.nix
    ./homebrew.nix
    ./launchd.nix
    ./nix-optimizations-darwin.nix
    # ./karabiner-elements.nix
    ./yabai.nix
  ];

  nix = {
    enable = true;
    settings = {
      ssl-cert-file = "/etc/nix/ca_cert.pem";
      sandbox = false;
      trusted-users = [
        "@admin"
        "root"
        "narinari"
      ];
    };
    extraOptions = ''
      sandbox = false
      trusted-users = @admin root narinari
    '';
    nixPath = mkForce nixPath;
  };

  # Too many packages try to spawn a server during their tests and connect to it,
  # so relax the sandbox to prevent build failures.
  # security.sandbox.profiles.allowLocalNetworking = true;

  # programs.bash.enable = false;

  system.defaults.ActivityMonitor.ShowCategory = null;
  system.activationScripts."ssl-ca-cert-fix".text = ''
    if [ ! -f /etc/nix/ca_cert.pem ]; then
      security export -t certs -f pemseq -k /Library/Keychains/System.keychain -o /tmp/certs-system.pem
      security export -t certs -f pemseq -k /System/Library/Keychains/SystemRootCertificates.keychain -o /tmp/certs-root.pem
      cat /tmp/certs-root.pem /tmp/certs-system.pem > /tmp/ca_cert.pem
      sudo mv /tmp/ca_cert.pem /etc/nix/
    fi
  '';

  security.pki.certificateFiles = [ ./ca_cert.pem ];
}
