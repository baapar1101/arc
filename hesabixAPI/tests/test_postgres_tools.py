from __future__ import annotations

from pathlib import Path

import pytest

from app.core.postgres_tools import (
    PostgreSQLToolNotFoundError,
    is_missing_debian_client_error,
    resolve_postgres_tool,
)


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


def test_posix_skips_debian_wrapper_and_uses_versioned_binary(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    wrapper = tmp_path / "path" / "pg_dump"
    wrapper.parent.mkdir()
    wrapper.write_text(
        "#!/usr/bin/perl\nexec '/usr/share/postgresql-common/pg_wrapper', @ARGV;\n",
        encoding="utf-8",
    )
    versioned = tmp_path / "pg" / "16" / "bin" / "pg_dump"
    versioned.parent.mkdir(parents=True)
    versioned.write_bytes(b"\x7fELF fake-pg-dump")

    monkeypatch.setattr(
        "app.core.postgres_tools._posix_postgresql_lib_root",
        lambda: tmp_path / "pg",
    )
    monkeypatch.setattr(
        "app.core.postgres_tools.shutil.which",
        lambda name, path=None: str(wrapper) if name == "pg_dump" else None,
    )

    result = resolve_postgres_tool(
        "pg_dump",
        environment={"PATH": str(wrapper.parent)},
        platform="posix",
    )

    assert result == versioned.resolve()


def test_posix_wrapper_without_client_raises_install_hint(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    wrapper = tmp_path / "pg_dump"
    wrapper.write_text(
        "#!/usr/bin/perl\nexec '/usr/share/postgresql-common/pg_wrapper', @ARGV;\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(
        "app.core.postgres_tools._posix_postgresql_lib_root",
        lambda: tmp_path / "missing-pg",
    )
    monkeypatch.setattr(
        "app.core.postgres_tools._installation_bin_dirs",
        lambda environment, platform: [],
    )
    monkeypatch.setattr(
        "app.core.postgres_tools.shutil.which",
        lambda name, path=None: str(wrapper) if name == "pg_dump" else None,
    )

    with pytest.raises(PostgreSQLToolNotFoundError, match="postgresql-client-<version>"):
        resolve_postgres_tool("pg_dump", environment={"PATH": str(tmp_path)}, platform="posix")


def test_debian_missing_client_stderr_is_detected() -> None:
    assert is_missing_debian_client_error(
        "Error: You must install at least one postgresql-client-<version> package\n"
    )
    assert not is_missing_debian_client_error("pg_dump: connection refused")
