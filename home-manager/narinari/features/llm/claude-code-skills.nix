# Claude Code の自作 Skill を ~/.claude/skills/<name>/SKILL.md に配備する。
#
# source-of-truth は ./claude/skills/<name>/SKILL.md (Nix store)。
# 既存の codex.nix / default.nix の activation pattern (diff+cp) を踏襲し、
# 中身が変わったときだけ unified diff を表示して上書きする。
#
# 追加対象 (現状):
# - codex-implement: Claude → codex CLI への実装委譲ワークフロー
#   (関連: home-manager/narinari/features/llm/codex.nix,
#    docs/codex-implement-claude-bridge.md)
{
  pkgs,
  lib,
  ...
}:

let
  codexImplementSkillFile = ./claude/skills/codex-implement/SKILL.md;
in
{
  home.activation.claudeCodexImplementSkill = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    skill_dir="$HOME/.claude/skills/codex-implement"
    skill_file="$skill_dir/SKILL.md"
    run mkdir -p "$skill_dir"
    if [ -f "$skill_file" ]; then
      if ! ${pkgs.diffutils}/bin/diff -q "$skill_file" "${codexImplementSkillFile}" > /dev/null 2>&1; then
        echo "claude: codex-implement/SKILL.md has changed:"
        ${pkgs.diffutils}/bin/diff -u "$skill_file" "${codexImplementSkillFile}" || true
      fi
    fi
    run cp -f "${codexImplementSkillFile}" "$skill_file"
    run chmod 644 "$skill_file"
  '';
}
