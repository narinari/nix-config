{ inputs, outputs, consig, pkgs, ... }:

{
  imports = [ ./global ./work ./darwin ./features/desktop/common ];
}
