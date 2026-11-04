"""Locate PostgreSQL command-line tools on Windows and POSIX hosts."""

from __future__ import annotations

import os
import re
import shutil
from collections.abc import Mapping
from pathlib import Path

_WRAPPER_MARKERS = (
    b"pg_wrapper",
    b"postgresql-common",
    b"postgresql-client-<version>",
)
_ELF_MAGIC = b"\x7fELF"
_PE_MAGIC = b"MZ"


class PostgreSQLToolNotFoundError(FileNotFoundError):
    """Raised when a required PostgreSQL client executable cannot be found."""


MISSING_CLIENT_MESSAGE_FA = (
    "ابزار {tool} یافت نشد یا روی سرور ناقص است. روی Ubuntu/Debian باید بسته "
    "postgresql-client-<نسخه> نصب شود (مثلاً postgresql-client-16)، نه فقط "
    "postgresql-client-common. با به‌روزرسانی Hesabix (hesabix -update) این بسته "
    "به‌صورت خودکار نصب می‌شود. در غیر این صورت HESABIX_POSTGRES_BIN_DIR را تنظیم کنید."
)


def missing_client_message_fa(tool: str) -> str:
    return MISSING_CLIENT_MESSAGE_FA.format(tool=tool)


def is_missing_debian_client_error(stderr: str) -> bool:
    text = (stderr or "").lower()
    return "postgresql-client-" in text and "must install" in text


def _version_key(path: Path) -> tuple[int, ...]:
    numbers = re.findall(r"\d+", path.name)
    return tuple(int(number) for number in numbers) or (0,)


def _posix_postgresql_lib_root() -> Path:
    return Path("/usr/lib/postgresql")


def _is_debian_pg_wrapper(path: Path) -> bool:
    """True for Debian/Ubuntu pg_wrapper stubs that are not a real client binary."""
    try:
        resolved = path
        try:
            resolved = path.resolve()
        except OSError:
            resolved = path
        resolved_name = resolved.name.lower()
        resolved_text = str(resolved).replace("\\", "/").lower()
        if resolved_name == "pg_wrapper" or "postgresql-common" in resolved_text:
            return True
        with path.open("rb") as handle:
            header = handle.read(2048)
    except OSError:
        return False
    if header.startswith(_ELF_MAGIC) or header.startswith(_PE_MAGIC):
        return False
    return any(marker in header for marker in _WRAPPER_MARKERS)


def _usable_tool_path(path: Path) -> Path | None:
    try:
        if not path.is_file():
            return None
        if _is_debian_pg_wrapper(path):
            return None
        return path.resolve()
    except OSError:
        return None


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

    directories: list[Path] = []
    version_root = _posix_postgresql_lib_root()
    try:
        versions = sorted(
            (entry for entry in version_root.iterdir() if entry.is_dir()),
            key=_version_key,
            reverse=True,
        )
    except OSError:
        versions = []
    directories.extend(version / "bin" for version in versions)
    directories.extend([Path("/usr/bin"), Path("/usr/local/bin")])
    return directories


def resolve_postgres_tool(
    tool: str,
    *,
    environment: Mapping[str, str] | None = None,
    platform: str | None = None,
) -> Path:
    """Resolve ``tool`` without assuming a shell-specific PATH layout.

    ``HESABIX_POSTGRES_BIN_DIR`` is authoritative when set. Otherwise PATH is
    searched, skipping Debian ``pg_wrapper`` stubs, then common PostgreSQL
    installation directories (versioned ``/usr/lib/postgresql/*/bin`` first).
    """
    environment = environment or os.environ
    platform = platform or os.name
    executable_name = f"{tool}.exe" if platform == "nt" else tool

    configured_dir = environment.get("HESABIX_POSTGRES_BIN_DIR", "").strip()
    if configured_dir:
        configured_path = Path(configured_dir).expanduser() / executable_name
        usable = _usable_tool_path(configured_path)
        if usable is not None:
            return usable
        raise PostgreSQLToolNotFoundError(
            f"{tool} was not found in HESABIX_POSTGRES_BIN_DIR: {configured_dir}"
        )

    path_value = environment.get("PATH")
    from_path = shutil.which(executable_name, path=path_value)
    if from_path:
        usable = _usable_tool_path(Path(from_path))
        if usable is not None:
            return usable

    for directory in _installation_bin_dirs(environment, platform):
        usable = _usable_tool_path(directory / executable_name)
        if usable is not None:
            return usable

    raise PostgreSQLToolNotFoundError(
        f"{tool} was not found or is only the Debian postgresql-client-common "
        "wrapper. Install postgresql-client-<version> (e.g. postgresql-client-16) "
        "or set HESABIX_POSTGRES_BIN_DIR."
    )
