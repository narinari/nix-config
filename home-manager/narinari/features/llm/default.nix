{
  config,
  lib,
  pkgs,
  ...
}:

let
  claude-notify = pkgs.writeShellScript "claude-notify" ''
    ${pkgs.deno}/bin/deno run --allow-read --allow-env --allow-run ${./claude/notify.ts}
  '';
  claude-statusline = pkgs.writeShellScript "claude-statusline" ''
    ${pkgs.deno}/bin/deno run --allow-read --allow-env ${./claude/statusline.ts}
  '';
  file-suggestion = pkgs.writeShellScript "file-suggestion" ''
    query=$(cat | ${pkgs.jq}/bin/jq -r '.query')
    cd "$CLAUDE_PROJECT_DIR"
    ${pkgs.fd}/bin/fd --hidden | ${pkgs.fzf}/bin/fzf --filter="$query" | head -20
  '';
in
{
  home.packages = with pkgs; [
    uv # for serena
    goose-cli
  ];

  programs.claude-code = {
    enable = true;
    settings = {
      permissions = {
        allow = [ ];
        defaultMode = "plan";
      };
      alwaysThinkingEnabled = true;
      hooks = {
        Stop = [
          {
            matcher = "";
            hooks = [
              {
                type = "command";
                command = claude-notify;
              }
            ];
          }
        ];
        Notification = [
          {
            matcher = "";
            hooks = [
              {
                type = "command";
                command = claude-notify;
              }
            ];
          }
        ];
      };
      statusLine = {
        type = "command";
        command = claude-statusline;
      };
      fileSuggestion = {
        type = "command";
        command = file-suggestion;
      };
    };
  };
}
