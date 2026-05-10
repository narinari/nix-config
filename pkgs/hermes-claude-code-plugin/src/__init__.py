"""Hermes plugin: delegate complex design tasks to Claude Code (Opus 4.7)."""

from __future__ import annotations

from .hooks import post_tool_call_logger
from .schemas import CLAUDE_CODE_SCHEMA
from .tools import claude_code_handler


def register(ctx) -> None:
    """Plugin entry point — invoked once by the Hermes plugin loader."""
    ctx.register_tool(
        name="claude_code",
        toolset="claude-code",
        schema=CLAUDE_CODE_SCHEMA,
        handler=claude_code_handler,
        emoji="🧠",
    )
    ctx.register_hook("post_tool_call", post_tool_call_logger)
