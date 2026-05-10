"""OpenAI tools-format schema for the claude_code delegate tool."""

from __future__ import annotations

CLAUDE_CODE_SCHEMA: dict = {
    "type": "function",
    "function": {
        "name": "claude_code",
        "description": (
            "Delegate a complex design / architecture / multi-file code-review task "
            "to Claude Code (Anthropic Opus 4.7) running as a subprocess. "
            "Use this when the task requires deep cross-file reasoning that exceeds "
            "the local model's capability — examples: 'review the auth module for "
            "security issues', 'design a migration plan for X', 'audit this codebase "
            "for race conditions'. Do NOT use for simple edits, single-line fixes, or "
            "questions that can be answered without reading code. Returns the model's "
            "response plus session_id (for follow-up via resume_session_id) and "
            "cost_usd (for telemetry)."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "task": {
                    "type": "string",
                    "description": (
                        "Full task description. Include background, constraints, and "
                        "the expected output format. Be explicit — the delegated agent "
                        "starts with no prior conversation context."
                    ),
                },
                "working_directory": {
                    "type": "string",
                    "description": (
                        "Absolute path to the project / git worktree the delegated "
                        "agent should run in. Defaults to the Hermes process cwd."
                    ),
                },
                "context_files": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": (
                        "Absolute paths to files Claude Code should read as context. "
                        "Surfaced to the agent as a 'Context files' section appended "
                        "to the task. The agent has Read permission on the working "
                        "directory; this list is a hint, not a sandbox."
                    ),
                },
                "resume_session_id": {
                    "type": "string",
                    "description": (
                        "Pass the session_id returned by a previous claude_code call "
                        "to continue that conversation. Use sparingly — each resume "
                        "replays the full prior context and accumulates cost."
                    ),
                },
                "timeout_seconds": {
                    "type": "integer",
                    "description": (
                        "Wall-clock timeout. Default 900 (15 min). Hard upper bound 1800. "
                        "On timeout the subprocess is killed and a partial result is returned."
                    ),
                    "minimum": 30,
                    "maximum": 1800,
                    "default": 900,
                },
            },
            "required": ["task"],
            "additionalProperties": False,
        },
    },
}
