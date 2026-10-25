"""Locate PostgreSQL command-line tools on Windows and POSIX hosts."""

from __future__ import annotations

import os
import re
import shutil
from collections.abc import Mapping
from pathlib import Path


class PostgreSQLToolNotFoundError(FileNotFoundError):
    """Raised when a required PostgreSQL client executable cannot be found."""


def _version_key(path: Path) -> tuple[int, ...]:
    numbers = re.findall(r"\d+", path.name)
    return tuple(int(number) for number in numbers) or (0,)


def _installation_bin_dirs(environment: Mapping[str, str], platform: str) -> list[Path]:
    if platform == "nt":
        roots: list[Path] = []
        for variable in ("ProgramFiles", "ProgramFiles(x86)"):
            value = environment.get(variable)
            if value:
                roots.append(Path(value) / "PostgreSQL")

        directories: list[Path] = []
        for root in roots:
            try:
                versions = sorted(
                    (entry for entry in root.iterdir() if entry.is_dir()),
                    key=_version_key,
                    reverse=True,
                )
            except OSError:
                continue
            directories.extend(version / "bin" for version in versions)
        return directories

    directories = [Path("/usr/bin"), Path("/usr/local/bin")]
    version_root = Path("/usr/lib/postgresql")
    try:
        versions = sorted(
            (entry for entry in version_root.iterdir() if entry.is_dir()),
            key=_version_key,
            reverse=True,
        )
    except OSError:
        versions = []
    directories.extend(version / "bin" for version in versions)
    return directories


def resolve_postgres_tool(
    tool: str,
    *,
    environment: Mapping[str, str] | None = None,
    platform: str | None = None,
) -> Path:
    """Resolve ``tool`` without assuming a shell-specific PATH layout.

    ``HESABIX_POSTGRES_BIN_DIR`` is authoritative when set. Otherwise the
    current PATH and common PostgreSQL installation directories are searched.
    """
    environment = environment or os.environ
    platform = platform or os.name
    executable_name = f"{tool}.exe" if platform == "nt" else tool

    configured_dir = environment.get("HESABIX_POSTGRES_BIN_DIR", "").strip()
    if configured_dir:
        configured_path = Path(configured_dir).expanduser() / executable_name
        if configured_path.is_file():
            return configured_path.resolve()
        raise PostgreSQLToolNotFoundError(
            f"{tool} was not found in HESABIX_POSTGRES_BIN_DIR: {configured_dir}"
        )

    path_value = environment.get("PATH")
    from_path = shutil.which(executable_name, path=path_value)
    if from_path:
        return Path(from_path).resolve()

    for directory in _installation_bin_dirs(environment, platform):
        candidate = directory / executable_name
        if candidate.is_file():
            return candidate.resolve()

    raise PostgreSQLToolNotFoundError(
        f"{tool} was not found. Install PostgreSQL client tools or set HESABIX_POSTGRES_BIN_DIR."
    )
