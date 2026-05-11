"""Tool schema for the claude_code delegate tool.

Hermes expects a flat `{name, description, parameters}` dict here. The plugin
loader wraps it as `{"type": "function", "function": ...}` at LLM-call time
(`hermes_cli/plugins.py:registry.get_definitions`), so manually wrapping it
again would double-nest and break parameter discovery.
"""

from __future__ import annotations

CLAUDE_CODE_SCHEMA: dict = {
    "name": "claude_code",
    "description": (
        "Delegate a complex design / architecture / multi-file code-review task "
        "to Claude Code (Anthropic Opus 4.7) running as a subprocess.\n\n"
        "USE for tasks requiring deep cross-file reasoning beyond the local model: "
        "'review the auth module for security issues', 'design a migration plan for X', "
        "'audit codebase for race conditions', 'plan a multi-file refactor with rollback', "
        "'propose an architecture for feature Y considering existing constraints'.\n\n"
        "DO NOT USE for: simple factual lookups, single-line fixes, conversational "
        "replies, tasks answerable without reading code, or anything where the local "
        "model is sufficient — calling claude_code is expensive (Opus 4.7 per call).\n\n"
        "Returns JSON with the assistant response text, session_id (for follow-up via "
        "resume_session_id), model, cost_usd (for telemetry), exit_code and elapsed_ms."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "task": {
                "type": "string",
                "description": (
                    "Full task description. Include background, constraints, and the "
                    "expected output format. The delegated agent starts with no prior "
                    "conversation context, so be explicit and self-contained."
                ),
            },
            "working_directory": {
                "type": "string",
                "description": (
                    "Absolute path to the project / git worktree the delegated agent "
                    "should run in. Defaults to the Hermes process cwd."
                ),
            },
            "context_files": {
                "type": "array",
                "items": {"type": "string"},
                "description": (
                    "Absolute paths to files Claude Code should read as context. "
                    "Surfaced to the agent as a 'Context files' section appended to "
                    "the task. The agent has Read permission on the working directory; "
                    "this list is a hint, not a sandbox."
                ),
            },
            "resume_session_id": {
                "type": "string",
                "description": (
                    "Pass the session_id returned by a previous claude_code call to "
                    "continue that conversation. Use sparingly — each resume replays "
                    "the full prior context and accumulates cost."
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
}
