{
  config,
  lib,
  pkgs,
  ...
}:

let
  # secret-tool の属性セット（全スクリプトで共有）
  secretAttrs = "service bw type session";

  bw-unlock = pkgs.writeShellApplication {
    name = "bw-unlock";
    runtimeInputs = [
      pkgs.bitwarden-cli
      pkgs.libsecret
      pkgs.jq
    ];
    text = ''
      # keyringに既存セッションがあれば終了
      existing=$(secret-tool lookup ${secretAttrs} 2>/dev/null || true)
      if [[ -n "$existing" ]]; then
        echo "Already unlocked (session exists in keyring)"
        exit 0
      fi

      # ログイン状態チェック
      status=$(bw status | jq -r '.status')
      case "$status" in
        unauthenticated)
          echo "Not logged in. Running bw login..."
          session=$(bw login --raw)
          ;;
        locked)
          session=$(bw unlock --raw)
          ;;
        unlocked)
          echo "Already unlocked"
          exit 0
          ;;
        *)
          echo "Unknown status: $status" >&2
          exit 1
          ;;
      esac

      # keyringに保存
      printf '%s' "$session" | secret-tool store \
        --label='Bitwarden CLI Session' ${secretAttrs}
      echo "Session stored in keyring"
    '';
  };

  bw-lock = pkgs.writeShellApplication {
    name = "bw-lock";
    runtimeInputs = [
      pkgs.bitwarden-cli
      pkgs.libsecret
    ];
    text = ''
      bw lock 2>/dev/null || true
      secret-tool clear ${secretAttrs} 2>/dev/null || true
      echo "Session cleared from keyring and vault locked"
    '';
  };

  bw-get = pkgs.writeShellApplication {
    name = "bw-get";
    runtimeInputs = [
      pkgs.bitwarden-cli
      pkgs.libsecret
    ];
    text = ''
      item="''${1:?Usage: bw-get <item-name> [field]}"
      field="''${2:-password}"

      session=$(secret-tool lookup ${secretAttrs} 2>/dev/null || true)
      if [[ -z "$session" ]]; then
        echo "Session not found. Run: bw-unlock" >&2
        exit 1
      fi

      BW_SESSION="$session" bw get "$field" "$item"
    '';
  };
in
{
  home.packages = [
    bw-unlock
    bw-lock
    bw-get
    pkgs.gnome-keyring
  ];

  # gnome-keyring-daemon をsystemd userサービスとして起動
  # rin (headless LXC) ではPAM/GNOMEセッションがないため手動管理が必要
  systemd.user.services.gnome-keyring = {
    Unit = {
      Description = "GNOME Keyring secrets daemon";
      After = [ "dbus.socket" ];
      Requires = [ "dbus.socket" ];
    };
    Service = {
      ExecStart = "${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --start --foreground --components=secrets";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # direnv stdlib に `use bw` ヘルパーを追加
  # .envrc で `use bw` と書くだけでBW_SESSIONがセットされる
  programs.direnv.stdlib = lib.mkAfter ''
    use_bw() {
      local session
      session=$(${pkgs.libsecret}/bin/secret-tool lookup ${secretAttrs} 2>/dev/null || true)
      if [[ -z "$session" ]]; then
        log_error "No BW_SESSION found in keyring. Run: bw-unlock"
        return 1
      fi
      export BW_SESSION="$session"
      log_status "BW_SESSION loaded from keyring"
    }
  '';
}
