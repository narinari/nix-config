---
name: codex-implement
description: Delegate the implementation phase of a designed task to the local codex CLI (qwen3.6 via Tailscale Aperture), then review the produced diff yourself before accepting. Use when the design is settled and you want a cheap, fast local executor for the mechanical edits while keeping design and final review on Claude.
origin: nix-config (home-manager features/llm)
version: "0.1.0"
allowed-tools: Read Grep Glob Edit Write Bash(codex:*) Bash(git diff:*) Bash(git status:*) Bash(git stash:*) Bash(jq:*)
argument-hint: "[short task name, optional]"
---

# codex-implement

Use this when:

- the design / API shape / data flow is **already decided** (by you, in this conversation),
- the remaining work is mechanical edits across one or more files,
- you want to spend Claude budget on **review**, not on typing the patch.

Do not use when:

- the user is still exploring trade-offs (stay on Claude),
- the task touches secrets, infra, or anything that requires per-edit human judgement,
- aperture / `http://ai` is unreachable (fall back to direct Claude edits).

## Workflow

### Phase 1 — Design (Claude, mandatory)

Before calling codex, write a self-contained implementation spec including:

1. **Goal** — one sentence.
2. **Constraints** — file paths to touch (absolute), files NOT to touch, language/framework, repo style conventions.
3. **Interfaces / signatures** — exact function names, types, return shapes.
4. **Acceptance** — `nix build ...` / `cargo test` / `pytest -k ...` / `go test ./...` etc. the change must pass.
5. **Out of scope** — what codex should NOT do (rename unrelated symbols, reformat, touch lockfiles, etc.).

If any of (1)-(5) is unclear, **stop and call `AskUserQuestion`**.

### Phase 2 — Delegate to codex

```bash
codex exec \
  --json \
  --profile local_qwen3_6_coding \
  -C "<absolute repo root>" \
  --sandbox workspace-write \
  --output-last-message /tmp/codex-last-$$.md \
  "<spec from Phase 1, as a single prompt>"
```

Flag rationale:

- `--json` — JSON Lines on stdout (parse with `jq` if needed).
- `--profile local_qwen3_6_coding` — pinned to `qwen3.6:35b-a3b-coding-mxfp8` via Aperture (`http://ai/v1`). Defined in `~/.codex/config.toml`. (profile 名にドットを入れると TOML が table 階層として解釈してしまうのでアンダースコア区切り。)
- `-C` — repo root, not the shell pwd, so codex resolves relative paths consistently.
- `--sandbox workspace-write` — codex may edit files inside `-C` but not the wider system. Never use `danger-full-access` from this skill.
- `--output-last-message` — write only the final agent message to a temp file. Easier to read back than scrolling the JSON stream.

Variants:

- Need read access outside `-C` → add `--add-dir <other-repo>`.
- Read-only dry-run → `--sandbox read-only` (codex will explain what it *would* do without writing).
- Fallback model → `--profile local_gemma4` (faster, general) or `--profile local_qwen3_5` (older coding tune).

### Phase 3 — Review (Claude, mandatory)

After codex returns:

1. `git status` + `git diff --stat` to see scope.
2. For every changed file: `Read` it, compare against the Phase 1 spec.
3. Check the seven things codex routinely gets wrong:
   - **Out-of-scope edits** (formatting churn, unrelated renames, accidental import reordering).
   - **Type drift** — signatures matching the spec but call sites not updated.
   - **Test coverage** — codex tends to skip tests unless the spec explicitly demands them.
   - **Error handling** — silent `unwrap` / `as any` / bare `except`.
   - **Secret leakage** — printed env vars, hardcoded keys, logs of request bodies.
   - **Cross-platform** — `.nix` referencing `pkgs` that don't exist on macOS, hardcoded `/home/...` paths.
   - **Commit-message-shaped reasoning written into code comments** — strip.
4. If any issue is found, **do not patch inline**. Re-delegate with a tightened spec ("you previously did X, instead do Y because Z"), or take over and edit yourself.
5. When clean, summarise the diff back to the user with: files changed, lines +/-, acceptance checks you actually ran, residual risks.

## Failure handling

| Symptom | Likely cause | Action |
|---|---|---|
| `codex: error: connection refused` to `http://ai/v1` | Aperture down / not on tailnet | Tell the user. Do **not** silently fall back to a different model. |
| `model not found: qwen3.6:35b-a3b-coding-mxfp8` | hail-mary side hasn't pulled the tag | Suggest `curl -s http://ai/v1/models` to confirm, then either pull on hail-mary or fall back to `--profile local_qwen3_5`. |
| codex hangs > 5 min | first-call model load / context too large | Wrap with `timeout 300 codex exec ...`, shrink the spec, retry. |
| `--json` returns empty / non-JSON on stdout | version skew (`codex-cli` < 0.130) | Check `codex --version`; this skill assumes ≥ 0.130. |
| Patch produced but `git diff` shows zero changes | codex ran in `--sandbox read-only` by mistake, or `-C` pointed at the wrong dir | Re-run with explicit `--sandbox workspace-write` and correct repo root. |
| codex modified files outside the spec | spec was too loose | Revert with `git checkout -- <file>` (unstaged) and re-delegate with an explicit "do NOT touch X" line. |

## Cost & scope discipline

- One codex delegation per skill invocation. If you find yourself wanting a second call, ask the user first — often the right answer is "Claude finishes the rest inline".
- Never `git commit` from inside this skill. Diff hand-off to the user is the natural boundary.
- Never call this skill from inside another sub-agent automatically. The user should be able to see exactly when codex was invoked.

## Related

- Reverse direction (Hermes → Claude Code Opus): `docs/hermes-agent-claude-code-bridge.md`.
- codex config source of truth: `home-manager/narinari/features/llm/codex.nix`.
- Operational doc: `docs/codex-implement-claude-bridge.md`.
