"""Subprocess driver for the claude_code delegate tool.

Runs the `claude` CLI in headless print mode with stream-json output, parses
events line-by-line, and returns a structured JSON response Hermes can surface
to the user. Authentication is assumed to be pre-seeded under
`$CLAUDE_CONFIG_DIR/.credentials.json` (OAuth token from Claude Pro/Max sub).
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import time
from typing import Any

logger = logging.getLogger(__name__)

DEFAULT_MODEL = "claude-opus-4-7"
DEFAULT_TIMEOUT = 900
MAX_TIMEOUT = 1800

# Conservative default: read/edit/write within the worktree, plus read-only git
# inspection and code search. Destructive shell ops are denied below.
ALLOWED_TOOLS = ",".join(
    [
        "Read",
        "Edit",
        "Write",
        "Glob",
        "Grep",
        "WebFetch",
        "Bash(git log:*)",
        "Bash(git diff:*)",
        "Bash(git status:*)",
        "Bash(git show:*)",
        "Bash(rg:*)",
        "Bash(fd:*)",
    ]
)
DISALLOWED_TOOLS = ",".join(
    [
        "Bash(rm:*)",
        "Bash(curl:*)",
        "Bash(wget:*)",
        "Bash(sudo:*)",
        "Bash(systemctl:*)",
        "Bash(nix-env:*)",
        # Block recursive delegation: claude inside claude_code must not spawn
        # another `claude` subprocess.
        "Bash(claude:*)",
    ]
)

STDERR_TAIL_BYTES = 2000


def _build_command(
    task: str,
    *,
    model: str,
    resume: str | None,
    context_files: list[str],
) -> tuple[list[str], str]:
    """Build argv for the claude CLI. Returns (cmd, prompt_text)."""
    prompt = task
    if context_files:
        prompt = (
            f"{task}\n\n"
            "## Context files\n"
            + "\n".join(f"- {p}" for p in context_files)
        )

    cmd: list[str] = [
        "claude",
        "--print",
        "--output-format",
        "stream-json",
        "--include-partial-messages",
        "--verbose",
        "--model",
        model,
        "--permission-mode",
        "acceptEdits",
        "--allowedTools",
        ALLOWED_TOOLS,
        "--disallowedTools",
        DISALLOWED_TOOLS,
    ]
    if resume:
        cmd += ["--resume", resume]
    cmd += ["-p", prompt]
    return cmd, prompt


def _build_env() -> dict[str, str]:
    """Minimal env for the subprocess. Authentication via CLAUDE_CONFIG_DIR only."""
    home = os.environ.get("HOME") or "/var/lib/hermes"
    env: dict[str, str] = {
        "PATH": os.environ.get("PATH", "/run/current-system/sw/bin:/usr/bin:/bin"),
        "HOME": home,
        "LANG": os.environ.get("LANG", "ja_JP.UTF-8"),
        "CLAUDE_CONFIG_DIR": os.environ.get(
            "CLAUDE_CONFIG_DIR", f"{home}/.claude"
        ),
    }
    # ANTHROPIC_API_KEY is intentionally NOT forwarded — we rely on OAuth.
    return env


def _parse_stream_event(
    line: str,
    state: dict[str, Any],
) -> None:
    """Mutate *state* with deltas extracted from one stream-json line."""
    try:
        ev = json.loads(line)
    except json.JSONDecodeError:
        return

    ev_type = ev.get("type")
    if ev_type == "system" and ev.get("subtype") == "init":
        state["session_id"] = ev.get("session_id") or state.get("session_id")
        state["model_used"] = ev.get("model") or state.get("model_used")
        return

    if ev_type == "stream_event":
        delta = ev.get("event", {}).get("delta") or {}
        if delta.get("type") == "text_delta":
            state["chunks"].append(delta.get("text", ""))
        return

    if ev_type == "result":
        # Final summary event — terminal in the stream.
        state["session_id"] = ev.get("session_id") or state.get("session_id")
        state["cost_usd"] = ev.get("total_cost_usd", state.get("cost_usd", 0.0))
        result_text = ev.get("result")
        if isinstance(result_text, str) and result_text:
            # Some claude CLI versions emit the full assembled result here even
            # when text_delta streaming wasn't captured — prefer it.
            state["final_text"] = result_text


def _kill_safe(proc: subprocess.Popen) -> None:
    try:
        proc.kill()
    except Exception:  # pragma: no cover - defensive
        pass


def claude_code_handler(args: dict[str, Any], **_kwargs: Any) -> str:
    """Hermes tool handler. Returns a JSON string per Hermes conventions."""
    task = args.get("task")
    if not isinstance(task, str) or not task.strip():
        return json.dumps(
            {"error": "task is required and must be a non-empty string"},
            ensure_ascii=False,
        )

    cwd = args.get("working_directory") or os.getcwd()
    if not isinstance(cwd, str) or not os.path.isdir(cwd):
        return json.dumps(
            {"error": f"working_directory does not exist: {cwd!r}"},
            ensure_ascii=False,
        )

    timeout = int(args.get("timeout_seconds") or DEFAULT_TIMEOUT)
    timeout = max(30, min(timeout, MAX_TIMEOUT))

    resume = args.get("resume_session_id") or None
    context_files = args.get("context_files") or []
    if not isinstance(context_files, list):
        context_files = []

    model = os.environ.get("HERMES_CLAUDE_CODE_MODEL", DEFAULT_MODEL)
    cmd, _prompt = _build_command(
        task,
        model=model,
        resume=resume if isinstance(resume, str) else None,
        context_files=[p for p in context_files if isinstance(p, str)],
    )
    env = _build_env()

    state: dict[str, Any] = {
        "chunks": [],
        "final_text": None,
        "session_id": None,
        "model_used": None,
        "cost_usd": 0.0,
    }

    started = time.monotonic()
    try:
        proc = subprocess.Popen(
            cmd,
            cwd=cwd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,  # line-buffered
        )
    except FileNotFoundError:
        return json.dumps(
            {"error": "claude binary not found on PATH"},
            ensure_ascii=False,
        )

    try:
        assert proc.stdout is not None
        for line in proc.stdout:
            line = line.strip()
            if line:
                _parse_stream_event(line, state)
            if time.monotonic() - started > timeout:
                logger.warning("claude_code: timeout after %ss, killing", timeout)
                _kill_safe(proc)
                break
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            _kill_safe(proc)
            proc.wait(timeout=5)
    except Exception as exc:  # pragma: no cover - defensive
        # Per the Hermes plugin guide, tool handlers must never raise — they
        # should return a JSON-encoded error so the agent can recover gracefully.
        _kill_safe(proc)
        logger.exception("claude_code: handler aborted unexpectedly")
        return json.dumps(
            {
                "error": f"claude_code internal error: {type(exc).__name__}: {exc}",
                "elapsed_ms": int((time.monotonic() - started) * 1000),
            },
            ensure_ascii=False,
        )

    stderr_tail = ""
    if proc.stderr is not None:
        try:
            stderr_tail = proc.stderr.read()[-STDERR_TAIL_BYTES:]
        except Exception:  # pragma: no cover - defensive
            stderr_tail = ""

    elapsed_ms = int((time.monotonic() - started) * 1000)
    text = state["final_text"] or "".join(state["chunks"])

    return json.dumps(
        {
            "result": text,
            "session_id": state["session_id"],
            "model": state["model_used"] or model,
            "cost_usd": state["cost_usd"],
            "exit_code": proc.returncode,
            "elapsed_ms": elapsed_ms,
            "stderr_tail": stderr_tail,
        },
        ensure_ascii=False,
    )
