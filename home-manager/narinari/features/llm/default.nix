{
  config,
  lib,
  pkgs,
  ...
}:

let
  claude-notify = pkgs.writeShellScript "claude-notify" ''
    ${pkgs.deno}/bin/deno run --allow-read --allow-env --allow-run --allow-net ${./claude/notify.ts}
  '';
  claude-statusline = pkgs.writeShellScript "claude-statusline" ''
    ${pkgs.deno}/bin/deno run --allow-read --allow-env ${./claude/statusline.ts}
  '';
  file-suggestion = pkgs.writeShellScript "file-suggestion" ''
    query=$(cat | ${pkgs.jq}/bin/jq -r '.query')
    cd "$CLAUDE_PROJECT_DIR"
    ${pkgs.fd}/bin/fd --hidden | ${pkgs.fzf}/bin/fzf --filter="$query" | head -20
  '';
  claudeSettingsFile = pkgs.writeText "claude-settings.json" (
    builtins.toJSON {
      model = "opus";
      enabledPlugins = {
        "code-simplifier@claude-plugins-official" = true;
        "code-review@claude-plugins-official" = true;
      };
      language = "japanese";
      alwaysThinkingEnabled = true;
      permissions = {
        defaultMode = "plan";
        allow = [
          "Bash(git add:*)"
          "Bash(git branch:*)"
          "Bash(git checkout:*)"
          "Bash(git commit:*)"
          "Bash(git fetch:*)"
          "Bash(git grep:*)"
          "Bash(git log:*)"
          "Bash(git pull:*)"
          "Bash(git push:*)"
          "Bash(git rebase:*)"
          "Bash(git reset:*)"
          "Bash(git restore:*)"
          "Bash(git stash:*)"
          "Bash(git worktree:*)"
          "Bash(go build:*)"
          "Bash(go fmt:*)"
          "Bash(go list:*)"
          "Bash(go mod download:*)"
          "Bash(*go vet*)"
          "Bash(*go test*)"
          "Bash(make:*)"
          "Bash(gh pr create:*)"
          "Bash(gh pr edit:*)"
          "Bash(gh pr view:*)"
          "Bash(ls:*)"
          "Bash(find:*)"
          "Bash(grep:*)"
          "Bash(mkdir:*)"
          "Bash(tree:*)"
          "Read(//home/narinari/.claude/**)"
          "Read(//home/narinari/dev/src/github.com/C-FO/**)"
          "Read(//home/narinari/dev/src/github.com/microsoft/amplifier/**)"
          "Read(//home/narinari/go/pkg/mod/**)"
          "mcp__fdev-jira__get_issue"
          "mcp__fdev-circleci__get_build_failure_logs"
          "mcp__fdev-confluence__get_confluence_content"
          "mcp__fdev-confluence__search_confluence_contents"
          "mcp__fdev-github__get_commit"
          "mcp__fdev-github__get_file_contents"
          "mcp__fdev-github__list_commits"
          "mcp__fdev-github__list_tags"
          "mcp__fdev-github__pull_request_read"
          "mcp__fdev-github__update_pull_request"
          "mcp__fdev-github__search_code"
          "mcp__fdev-slack__get_slack_conversation_replies"
        ];
        deny = [ ];
      };
      hooks = {
        Stop = [
          {
            matcher = "";
            hooks = [
              {
                type = "command";
                command = toString claude-notify;
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
                command = toString claude-notify;
              }
            ];
          }
        ];
      };
      statusLine = {
        type = "command";
        command = toString claude-statusline;
      };
      fileSuggestion = {
        type = "command";
        command = toString file-suggestion;
      };
    }
  );
in
{
  home.packages = with pkgs; [
    uv # for serena
  ];

  programs.claude-code = {
    enable = true;
  };

  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings="$HOME/.claude/settings.json"
    run mkdir -p "$HOME/.claude"
    if [ -f "$settings" ]; then
      current=$(${pkgs.jq}/bin/jq --sort-keys . "$settings")
      desired=$(${pkgs.jq}/bin/jq --sort-keys . "${claudeSettingsFile}")
      if [ "$current" != "$desired" ]; then
        echo "claude: settings.json has changed:"
        ${pkgs.diffutils}/bin/diff -u <(echo "$current") <(echo "$desired") || true
      fi
    fi
    run cp -f "${claudeSettingsFile}" "$settings"
    run chmod 644 "$settings"
  '';
}
