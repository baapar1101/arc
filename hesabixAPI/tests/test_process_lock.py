from __future__ import annotations

from pathlib import Path

from app.core.process_lock import InterProcessFileLock, default_lock_path


def test_default_lock_path_uses_native_temp_directory() -> None:
    path = default_lock_path("hesabix-test.lock")

    assert path.name == "hesabix-test.lock"
    assert path.is_absolute()


def test_second_handle_cannot_acquire_held_lock(tmp_path: Path) -> None:
    path = tmp_path / "leader.lock"
    first = InterProcessFileLock(path)
    second = InterProcessFileLock(path)

    try:
        assert first.acquire() is True
        assert first.acquire() is True
        assert second.acquire() is False
    finally:
        first.release()
        second.release()

    assert second.acquire() is True
    second.release()


def test_owner_pid_is_written_without_releasing_lock(tmp_path: Path) -> None:
    lock = InterProcessFileLock(tmp_path / "owner.lock")

    try:
        assert lock.acquire() is True
        lock.write_owner_pid()
        assert InterProcessFileLock(lock.path).acquire() is False
    finally:
        lock.release()

    assert (tmp_path / "owner.lock").read_text(encoding="ascii").startswith("pid=")
