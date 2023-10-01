{ config, lib, pkgs, inputs, outputs, ... }:
let
  inherit (config.networking) hostName;
  hosts = outputs.nixosConfigurations;
  pubKey = host: ../../${host}/ssh_host_ed25519_key.pub;
in {
  # programs.ssh = {
  #   # Each hosts public key
  #   knownHosts = builtins.mapAttrs (name: _: {
  #     publicKeyFile = pubKey name;
  #     extraHostNames = lib.optional (name == hostName)
  #       "localhost"; # Alias for localhost if it's the same host
  #   }) hosts;
  # };
}
