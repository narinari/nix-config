{ inputs, outputs, consig, pkgs, ... }:

{
  imports =
    [ ./global ./features/cli ./work ./darwin ./features/desktop/common ];
}
