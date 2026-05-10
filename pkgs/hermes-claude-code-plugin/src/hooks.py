"""post_tool_call hook for claude_code — emits structured telemetry to logs."""

from __future__ import annotations

import json
import logging
from typing import Any

logger = logging.getLogger("hermes.plugin.claude_code")


def post_tool_call_logger(
    tool_name: str = "",
    args: dict[str, Any] | None = None,
    result: Any = None,
    task_id: str = "",
    session_id: str = "",
    tool_call_id: str = "",
    **_: Any,
) -> None:
    """Log one structured line per claude_code invocation.

    Picked up by journalctl as Hermes process logs. Grep for
    `hermes.plugin.claude_code` to enumerate delegations or `cost_usd=` to sum
    spend.
    """
    if tool_name != "claude_code":
        return

    payload: dict[str, Any] = {}
    if isinstance(result, str):
        try:
            payload = json.loads(result)
        except json.JSONDecodeError:
            payload = {"raw": result[:200]}

    task_preview = ""
    if isinstance(args, dict):
        t = args.get("task")
        if isinstance(t, str):
            task_preview = t.replace("\n", " ")[:200]

    logger.info(
        "claude_code call: parent_session=%s task_id=%s tool_call_id=%s "
        "delegated_session=%s model=%s cost_usd=%.4f exit_code=%s elapsed_ms=%s "
        "task=%r",
        session_id,
        task_id,
        tool_call_id,
        payload.get("session_id"),
        payload.get("model"),
        float(payload.get("cost_usd") or 0.0),
        payload.get("exit_code"),
        payload.get("elapsed_ms"),
        task_preview,
    )
