from __future__ import annotations

from pathlib import Path

from app.core import runtime_paths
from app.core.settings import get_settings


def test_windows_data_path_uses_local_app_data(tmp_path: Path) -> None:
    result = runtime_paths.application_data_dir(
        {"LOCALAPPDATA": str(tmp_path)},
        platform="nt",
    )

    assert result == tmp_path.resolve() / "Hesabix"


def test_posix_data_path_keeps_production_default() -> None:
    assert runtime_paths.application_data_dir({}, platform="posix") == Path("/var/lib/hesabix")


def test_path_overrides_are_resolved_from_api_root() -> None:
    assert (
        runtime_paths.settings_env_file({"HESABIX_ENV_FILE": "config/test.env"})
        == (runtime_paths.API_ROOT / "config" / "test.env").resolve()
    )
    assert (
        runtime_paths.docs_root({"HESABIX_DOCS_DIR": "../custom-docs"})
        == (runtime_paths.REPOSITORY_ROOT / "custom-docs").resolve()
    )


def test_default_docs_root_matches_repository_layout() -> None:
    assert runtime_paths.docs_root() == runtime_paths.REPOSITORY_ROOT / "docs"
    assert runtime_paths.docs_root().is_dir()


def test_settings_env_file_is_independent_of_working_directory(
    monkeypatch,
    tmp_path: Path,
) -> None:
    env_file = tmp_path / "test.env"
    env_file.write_text("APP_NAME=loaded-from-explicit-env\n", encoding="utf-8")
    unrelated_cwd = tmp_path / "unrelated"
    unrelated_cwd.mkdir()
    monkeypatch.setenv("HESABIX_ENV_FILE", str(env_file))
    monkeypatch.chdir(unrelated_cwd)
    get_settings.cache_clear()

    try:
        assert get_settings().app_name == "loaded-from-explicit-env"
    finally:
        get_settings.cache_clear()


def test_file_storage_override_is_cross_platform(tmp_path: Path) -> None:
    storage_root = tmp_path / "files"

    result = runtime_paths.file_storage_dir(
        {"HESABIX_FILE_STORAGE_DIR": str(storage_root)}
    )

    assert result == storage_root.resolve()
