{ config, lib, pkgs, ... }:

{
  # age.secrets.work_env.file = "${pkgs.my-secrets.outPath}/work/env.age";
  programs.zsh = {
    enable = true;
    plugins = [{
      name = "work-config";
      src = lib.cleanSource ./work-config;
    }];
  };
}
