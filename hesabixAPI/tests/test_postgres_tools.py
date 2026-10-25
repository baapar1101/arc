from __future__ import annotations

from pathlib import Path

import pytest

from app.core.postgres_tools import PostgreSQLToolNotFoundError, resolve_postgres_tool


def test_configured_windows_bin_directory_is_authoritative(tmp_path: Path) -> None:
    executable = tmp_path / "psql.exe"
    executable.write_bytes(b"")

    result = resolve_postgres_tool(
        "psql",
        environment={"HESABIX_POSTGRES_BIN_DIR": str(tmp_path), "PATH": ""},
        platform="nt",
    )

    assert result == executable.resolve()


def test_invalid_configured_directory_does_not_fall_back_to_path(
    tmp_path: Path,
) -> None:
    with pytest.raises(PostgreSQLToolNotFoundError, match="HESABIX_POSTGRES_BIN_DIR"):
        resolve_postgres_tool(
            "pg_dump",
            environment={
                "HESABIX_POSTGRES_BIN_DIR": str(tmp_path / "missing"),
                "PATH": str(tmp_path),
            },
            platform="nt",
        )


def test_windows_installations_are_searched_newest_first(tmp_path: Path) -> None:
    old_bin = tmp_path / "PostgreSQL" / "15" / "bin"
    new_bin = tmp_path / "PostgreSQL" / "16" / "bin"
    old_bin.mkdir(parents=True)
    new_bin.mkdir(parents=True)
    (old_bin / "psql.exe").write_bytes(b"")
    expected = new_bin / "psql.exe"
    expected.write_bytes(b"")

    result = resolve_postgres_tool(
        "psql",
        environment={"ProgramFiles": str(tmp_path), "PATH": ""},
        platform="nt",
    )

    assert result == expected.resolve()


def test_posix_path_resolution_does_not_add_windows_suffix(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    executable = tmp_path / "pg_dump"
    executable.write_bytes(b"")
    monkeypatch.setattr(
        "app.core.postgres_tools.shutil.which",
        lambda name, path=None: str(executable) if name == "pg_dump" else None,
    )

    result = resolve_postgres_tool("pg_dump", environment={"PATH": str(tmp_path)}, platform="posix")

    assert result == executable.resolve()
