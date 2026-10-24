"""Lazy, cross-platform initialization for WeasyPrint.

Windows needs its native Pango/GTK DLL directories registered before the
first WeasyPrint import. POSIX loaders do not need this setup.
"""

from __future__ import annotations

import importlib
import os
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any


class WeasyPrintRuntimeError(RuntimeError):
    """Raised when WeasyPrint or its native runtime cannot be initialized."""


@dataclass(frozen=True)
class WeasyPrintRuntime:
    HTML: Any
    CSS: Any
    FontConfiguration: Any


_runtime: WeasyPrintRuntime | None = None
_runtime_lock = threading.Lock()
_dll_directory_handles: list[Any] = []


def _configured_dll_directories(environment: dict[str, str]) -> tuple[list[Path], bool]:
    configured = environment.get("HESABIX_WEASYPRINT_DLL_DIRS", "").strip()
    if not configured:
        configured = environment.get("WEASYPRINT_DLL_DIRECTORIES", "").strip()
    if configured:
        return (
            [Path(value).expanduser() for value in configured.split(os.pathsep) if value],
            True,
        )

    return (
        [
            Path(r"C:\msys64\ucrt64\bin"),
            Path(r"C:\msys64\mingw64\bin"),
            Path(r"C:\Program Files\GTK3-Runtime Win64\bin"),
        ],
        False,
    )


def _prepare_windows_dll_search(environment: dict[str, str]) -> None:
    directories, explicitly_configured = _configured_dll_directories(environment)
    existing = [directory.resolve() for directory in directories if directory.is_dir()]
    if explicitly_configured and len(existing) != len(directories):
        missing = [str(directory) for directory in directories if not directory.is_dir()]
        raise WeasyPrintRuntimeError(
            "Configured WeasyPrint DLL directories do not exist: " + ", ".join(missing)
        )

    if existing:
        # WeasyPrint also reads this variable during import. Keep its established
        # variable in sync with the Hesabix-specific setting.
        environment["WEASYPRINT_DLL_DIRECTORIES"] = os.pathsep.join(map(str, existing))

    add_dll_directory = getattr(os, "add_dll_directory", None)
    if add_dll_directory is None:
        return
    for directory in existing:
        _dll_directory_handles.append(add_dll_directory(str(directory)))


def load_weasyprint() -> WeasyPrintRuntime:
    """Load WeasyPrint once, after preparing native Windows dependencies."""
    global _runtime
    if _runtime is not None:
        return _runtime

    with _runtime_lock:
        if _runtime is not None:
            return _runtime
        if os.name == "nt":
            _prepare_windows_dll_search(os.environ)
        try:
            weasyprint = importlib.import_module("weasyprint")
            fonts = importlib.import_module("weasyprint.text.fonts")
        except (ImportError, OSError) as exc:
            raise WeasyPrintRuntimeError(
                "WeasyPrint could not load its Python or native dependencies. "
                "On Windows, install the MSYS2/GTK runtime or set "
                "HESABIX_WEASYPRINT_DLL_DIRS."
            ) from exc

        _runtime = WeasyPrintRuntime(
            HTML=weasyprint.HTML,
            CSS=weasyprint.CSS,
            FontConfiguration=fonts.FontConfiguration,
        )
        return _runtime
