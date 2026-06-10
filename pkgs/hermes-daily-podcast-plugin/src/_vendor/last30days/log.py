"""Shared logging utilities for last30days skill.

Vendored from mvanhorn/last30days-skill @ 122158415ae421da83e739f2668032f6bc78d39c
(skills/last30days/scripts/lib/log.py).

Hermes plugin specific differences (see ../UPSTREAM.md):
- Honour ``HERMES_PODCAST_VENDOR_DEBUG`` in addition to ``LAST30DAYS_DEBUG`` so
  the host plugin can flip vendor stderr noise from a single env without
  patching upstream files.
- ``source_log`` defaults to ``tty_only=False`` upstream; we keep that signature
  but the plugin gates stderr globally on the same env so non-interactive
  systemd journals stay clean by default.
"""

import os
import sys

DEBUG = (
    os.environ.get("LAST30DAYS_DEBUG", "").lower() in ("1", "true", "yes")
    or os.environ.get("HERMES_PODCAST_VENDOR_DEBUG", "").lower() in ("1", "true", "yes")
)


def debug(msg: str) -> None:
    """Log debug message to stderr (only when debug env is set)."""
    if DEBUG:
        sys.stderr.write(f"[DEBUG] {msg}\n")
        sys.stderr.flush()


def source_log(prefix: str, msg: str, *, tty_only: bool = True) -> None:
    """Log a source module message to stderr.

    Args:
        prefix: Source label (e.g. "Reddit", "Bird").
        msg: Message text.
        tty_only: If True, only log when stderr is a TTY (avoids cluttering
                  non-interactive output like systemd journals).
    """
    if not DEBUG:
        return
    if tty_only and not sys.stderr.isatty():
        return
    sys.stderr.write(f"[{prefix}] {msg}\n")
    sys.stderr.flush()
