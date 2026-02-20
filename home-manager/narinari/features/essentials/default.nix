{
  config,
  lib,
  pkgs,
  outputs,
  ...
}:

{
  imports = [
    ./btop.nix
    ./direnv.nix
    ./git.nix
    ./gnupg.nix
    ./lf.nix
    ./less.nix
    ./ssh.nix
    ./tmux.nix
    ./zsh.nix
  ];

  home.sessionVariables = {
    COLORTERM = "truecolor";
  };

  home.packages = with pkgs; [
    # nix
    cachix
    comma # Install and run programs by sticking a , before them
    nix-update
    nixpkgs-fmt
    nixos-shell
    manix

    ripgrep # Better grep
    fd # Better find
    httpie # Better curl
    rage
    sops
    zstd
  ];

  programs.bash = {
    enable = true;
    bashrcExtra = ''
      # Fix getcwd error when current directory no longer exists
      if ! pwd >/dev/null 2>&1; then
        cd "$HOME" 2>/dev/null || cd /
      fi

      if command -v direnv >/dev/null 2>&1; then
        if [ -n "$CLAUDECODE" ]; then
          eval "$(direnv hook bash)"
          eval "$(DIRENV_LOG_FORMAT= direnv export bash)"
        fi
      fi
    '';
  };
}
