"""Central, OS-aware runtime paths for the API."""

from __future__ import annotations

import os
from collections.abc import Mapping
from pathlib import Path

API_ROOT = Path(__file__).resolve().parents[2]
REPOSITORY_ROOT = API_ROOT.parent


def _absolute_override(value: str, *, relative_to: Path = API_ROOT) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = relative_to / path
    return path.resolve()


def settings_env_file(environment: Mapping[str, str] | None = None) -> Path:
    """Return an explicit env file or the API-root ``.env`` file."""
    if environment is None:
        environment = os.environ
    configured = environment.get("HESABIX_ENV_FILE", "").strip()
    return _absolute_override(configured) if configured else API_ROOT / ".env"


def application_data_dir(
    environment: Mapping[str, str] | None = None,
    *,
    platform: str | None = None,
) -> Path:
    """Return a persistent application-data directory for the current OS."""
    if environment is None:
        environment = os.environ
    configured = environment.get("HESABIX_DATA_DIR", "").strip()
    if configured:
        return _absolute_override(configured)

    platform = platform or os.name
    if platform == "nt":
        windows_root = (
            environment.get("LOCALAPPDATA")
            or environment.get("PROGRAMDATA")
            or environment.get("TEMP")
        )
        if windows_root:
            return Path(windows_root).expanduser().resolve() / "Hesabix"
        return API_ROOT / ".runtime-data"
    return Path("/var/lib/hesabix")


def file_storage_dir(environment: Mapping[str, str] | None = None) -> Path:
    if environment is None:
        environment = os.environ
    configured = environment.get("HESABIX_FILE_STORAGE_DIR", "").strip()
    if configured:
        return _absolute_override(configured)
    return application_data_dir(environment) / "files"


def voice_data_dir(environment: Mapping[str, str] | None = None) -> Path:
    return application_data_dir(environment) / "voice-data"


def docs_root(environment: Mapping[str, str] | None = None) -> Path:
    if environment is None:
        environment = os.environ
    configured = environment.get("HESABIX_DOCS_DIR", "").strip()
    if configured:
        return _absolute_override(configured)
    return REPOSITORY_ROOT / "docs"
