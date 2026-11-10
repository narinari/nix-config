"""Xvfb (仮想 X ディスプレイ) のライフサイクル管理。

GOLD POINT CARD+ は headless Chromium のログイン POST を "Access Denied" で拒否する
(Akamai)。そのため Chromium は headed で起動し、表示先として画面を持たない Xvfb を使う。

`Xvfb -displayfd <fd>` で空いているディスプレイ番号を Xvfb 自身に選ばせ、pipe から
読み取る (固定番号の衝突を避ける)。
"""

from __future__ import annotations

import os
import select
import shutil
import subprocess
import time

XVFB_START_TIMEOUT_SECONDS = 10
XVFB_STOP_TIMEOUT_SECONDS = 5
XVFB_SCREEN = "1366x768x24"


class XvfbError(Exception):
    """Xvfb の起動・停止の失敗。"""


class VirtualDisplay:
    """Xvfb を 1 つ起動し、DISPLAY 値 (":N") を返す。stop() で必ず終了させる。"""

    def __init__(self, binary: str) -> None:
        self._binary = binary
        self._proc: subprocess.Popen | None = None

    def start(self) -> str:
        resolved = shutil.which(self._binary) or self._binary
        read_fd, write_fd = os.pipe()
        try:
            self._proc = subprocess.Popen(
                [
                    resolved,
                    "-displayfd",
                    str(write_fd),
                    "-screen",
                    "0",
                    XVFB_SCREEN,
                    "-nolisten",
                    "tcp",
                ],
                pass_fds=(write_fd,),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except FileNotFoundError as exc:
            os.close(read_fd)
            os.close(write_fd)
            raise XvfbError(f"Xvfb binary not found: {self._binary}") from exc
        os.close(write_fd)
        try:
            return f":{self._read_display_number(read_fd)}"
        except XvfbError:
            self.stop()
            raise
        finally:
            os.close(read_fd)

    def _read_display_number(self, read_fd: int) -> int:
        deadline = time.monotonic() + XVFB_START_TIMEOUT_SECONDS
        buf = b""
        while not buf.endswith(b"\n"):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise XvfbError("timed out waiting for Xvfb display number")
            ready, _, _ = select.select([read_fd], [], [], remaining)
            if not ready:
                continue
            chunk = os.read(read_fd, 64)
            if not chunk:
                code = self._proc.poll() if self._proc else None
                raise XvfbError(f"Xvfb exited before reporting a display (code={code})")
            buf += chunk
        try:
            return int(buf.strip())
        except ValueError as exc:
            raise XvfbError("Xvfb reported an invalid display number") from exc

    def stop(self) -> None:
        if self._proc is not None and self._proc.poll() is None:
            self._proc.terminate()
            try:
                self._proc.wait(timeout=XVFB_STOP_TIMEOUT_SECONDS)
            except subprocess.TimeoutExpired:
                self._proc.kill()
        self._proc = None
