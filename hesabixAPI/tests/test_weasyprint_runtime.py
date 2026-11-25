from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

import pytest

from app.core import weasyprint_runtime


def test_load_is_lazy_and_prepares_windows_before_import(monkeypatch) -> None:
    events: list[str] = []
    fake_html = object()
    fake_css = object()
    fake_font_configuration = object()

    monkeypatch.setattr(weasyprint_runtime, "_runtime", None)
    monkeypatch.setattr(
        weasyprint_runtime,
        "_prepare_windows_dll_search",
        lambda environment: events.append("prepare"),
    )

    def fake_import(name: str):
        events.append(f"import:{name}")
        if name == "weasyprint":
            return SimpleNamespace(HTML=fake_html, CSS=fake_css)
        return SimpleNamespace(FontConfiguration=fake_font_configuration)

    monkeypatch.setattr(weasyprint_runtime.importlib, "import_module", fake_import)

    runtime = weasyprint_runtime.load_weasyprint()

    assert events == [
        "prepare",
        "import:weasyprint",
        "import:weasyprint.text.fonts",
    ]
    assert runtime.HTML is fake_html
    assert runtime.CSS is fake_css
    assert runtime.FontConfiguration is fake_font_configuration


def test_explicit_dll_directories_are_registered_and_handles_retained(
    monkeypatch,
    tmp_path: Path,
) -> None:
    first = tmp_path / "first"
    second = tmp_path / "second"
    first.mkdir()
    second.mkdir()
    handles: list[object] = []

    def fake_add_dll_directory(path: str) -> object:
        handle = object()
        handles.append(handle)
        assert Path(path) in {first.resolve(), second.resolve()}
        return handle

    monkeypatch.setattr(weasyprint_runtime, "_dll_directory_handles", [])
    monkeypatch.setattr(weasyprint_runtime.os, "add_dll_directory", fake_add_dll_directory)
    environment = {"HESABIX_WEASYPRINT_DLL_DIRS": f"{first}{weasyprint_runtime.os.pathsep}{second}"}

    weasyprint_runtime._prepare_windows_dll_search(environment)

    assert environment["WEASYPRINT_DLL_DIRECTORIES"] == (
        f"{first.resolve()}{weasyprint_runtime.os.pathsep}{second.resolve()}"
    )
    assert weasyprint_runtime._dll_directory_handles == handles


def test_missing_explicit_dll_directory_fails_with_clear_error(tmp_path: Path) -> None:
    missing = tmp_path / "missing"

    with pytest.raises(
        weasyprint_runtime.WeasyPrintRuntimeError,
        match="do not exist",
    ):
        weasyprint_runtime._prepare_windows_dll_search(
            {"HESABIX_WEASYPRINT_DLL_DIRS": str(missing)}
        )


def test_real_weasyprint_runtime_renders_pdf_on_current_platform() -> None:
    runtime = weasyprint_runtime.load_weasyprint()
    pdf = runtime.HTML(string="<html><body><p>Hello حسابیکس</p></body></html>").write_pdf(
        font_config=runtime.FontConfiguration()
    )

    assert pdf.startswith(b"%PDF-")
    assert len(pdf) > 1000
