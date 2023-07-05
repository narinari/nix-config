{ pkgs, inputs, ... }:

{
  imports = [ ../common/global ../common/darwin ../common/users/narinari ];

  networking = { hostName = "FL4N2RD4TD"; };

  # Add ability to used TouchID for sudo authentication
  security.pam.enableSudoTouchIdAuth = true;
}
