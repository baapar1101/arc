from __future__ import annotations

import gzip
import subprocess
from pathlib import Path
from types import SimpleNamespace

from app.services.database_backup_service import DatabaseBackupService
from app.services.database_restore_service import DatabaseRestoreService


def _settings() -> SimpleNamespace:
    return SimpleNamespace(
        db_host="localhost",
        db_port=5432,
        db_user="hesabix",
        db_password="secret-for-test",
        db_name="hesabix_test",
    )


def test_backup_uses_resolved_pg_dump_without_rewriting_path(monkeypatch) -> None:
    service = DatabaseBackupService.__new__(DatabaseBackupService)
    service.db = None
    service.settings = _settings()
    observed: dict[str, object] = {}

    def fake_resolve(tool, *, environment):
        observed["resolver_path"] = environment.get("PATH")
        assert tool == "pg_dump"
        return Path("C:/PostgreSQL/16/bin/pg_dump.exe")

    def fake_run(command, **kwargs):
        observed["command"] = command
        observed["run_path"] = kwargs["env"].get("PATH")
        return subprocess.CompletedProcess(command, 0, stdout=b"SELECT 1;", stderr=b"")

    monkeypatch.setenv("PATH", "original-test-path")
    monkeypatch.setattr("app.services.database_backup_service.resolve_postgres_tool", fake_resolve)
    monkeypatch.setattr("app.services.database_backup_service.subprocess.run", fake_run)

    assert service.create_backup(compress=False) == b"SELECT 1;"
    assert observed["command"][0] == "C:\\PostgreSQL\\16\\bin\\pg_dump.exe"
    assert observed["resolver_path"] == "original-test-path"
    assert observed["run_path"] == "original-test-path"


def test_gzip_restore_is_expanded_before_psql_and_temp_file_is_removed(
    monkeypatch,
    tmp_path: Path,
) -> None:
    backup_path = tmp_path / "backup.sql.gz"
    with gzip.open(backup_path, "wb") as compressed:
        compressed.write(b"SELECT 42;\n")

    service = DatabaseRestoreService.__new__(DatabaseRestoreService)
    service.settings = _settings()
    service._on_progress = lambda _percent, _message: None
    commands: list[list[str]] = []
    restore_sql_path: Path | None = None

    monkeypatch.setattr(
        "app.services.database_restore_service.resolve_postgres_tool",
        lambda tool, *, environment: Path("C:/PostgreSQL/16/bin/psql.exe"),
    )

    def fake_run(command, **kwargs):
        nonlocal restore_sql_path
        commands.append(command)
        if "-f" in command:
            restore_sql_path = Path(command[command.index("-f") + 1])
            assert restore_sql_path != backup_path
            assert restore_sql_path.read_bytes() == b"SELECT 42;\n"
        return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr("app.services.database_restore_service.subprocess.run", fake_run)

    service.restore(str(backup_path))

    assert len(commands) == 4
    assert all(command[0].endswith("psql.exe") for command in commands)
    assert restore_sql_path is not None
    assert not restore_sql_path.exists()
