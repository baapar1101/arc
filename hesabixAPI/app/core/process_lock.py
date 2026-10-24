"""Cross-platform, process-scoped file locks.

The lock is advisory and local to one host.  It is intended to elect one
leader among multiple application worker processes without coupling startup to
the database.
"""

from __future__ import annotations

import errno
import importlib
import os
import tempfile
from pathlib import Path
from typing import BinaryIO


def default_lock_path(filename: str) -> Path:
    """Return a writable OS-native temporary path for a lock file."""
    return Path(tempfile.gettempdir()) / filename


class InterProcessFileLock:
    """Hold a non-blocking exclusive lock until :meth:`release` is called."""

    def __init__(self, path: str | os.PathLike[str]):
        self.path = Path(path)
        self._handle: BinaryIO | None = None

    @property
    def acquired(self) -> bool:
        return self._handle is not None

    def acquire(self) -> bool:
        """Try to acquire the lock, returning ``False`` when it is contended."""
        if self._handle is not None:
            return True

        self.path.parent.mkdir(parents=True, exist_ok=True)
        handle = self.path.open("a+b")
        try:
            # msvcrt.locking locks bytes, so make sure byte zero exists.
            handle.seek(0, os.SEEK_END)
            if handle.tell() == 0:
                handle.write(b"\0")
                handle.flush()
            handle.seek(0)

            if os.name == "nt":
                import msvcrt

                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            elif os.name == "posix":
                fcntl = importlib.import_module("fcntl")

                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            else:
                raise RuntimeError(f"Unsupported process-lock platform: {os.name}")
        except OSError as exc:
            handle.close()
            if exc.errno in {errno.EACCES, errno.EAGAIN, errno.EDEADLK}:
                return False
            raise
        except Exception:
            handle.close()
            raise

        self._handle = handle
        return True

    def write_owner_pid(self) -> None:
        """Write diagnostic ownership metadata without releasing the lock."""
        if self._handle is None:
            raise RuntimeError("Cannot write lock metadata before acquiring the lock")
        self._handle.seek(0)
        self._handle.truncate()
        self._handle.write(f"pid={os.getpid()}\n".encode("ascii"))
        self._handle.flush()
        self._handle.seek(0)

    def release(self) -> None:
        handle = self._handle
        if handle is None:
            return

        self._handle = None
        try:
            handle.seek(0)
            if os.name == "nt":
                import msvcrt

                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            elif os.name == "posix":
                fcntl = importlib.import_module("fcntl")

                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        finally:
            handle.close()

    def __enter__(self) -> InterProcessFileLock:
        if not self.acquire():
            raise BlockingIOError(f"Lock is already held: {self.path}")
        return self

    def __exit__(self, *_args: object) -> None:
        self.release()
