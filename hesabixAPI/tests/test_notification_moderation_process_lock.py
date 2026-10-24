from __future__ import annotations

from pathlib import Path

from app.workers import notification_moderation_worker as worker


def test_moderation_worker_lock_is_cross_platform(
    monkeypatch,
    tmp_path: Path,
) -> None:
    monkeypatch.setenv(
        "HESABIX_NOTIFICATION_MODERATION_LOCKFILE",
        str(tmp_path / "moderation.lock"),
    )
    worker._release_lock()

    try:
        assert worker._acquire_lock() is True
        assert worker._worker_lock is not None
        assert worker._worker_lock.acquired is True
    finally:
        worker._release_lock()

    assert worker._worker_lock is None
