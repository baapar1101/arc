from __future__ import annotations

import importlib.util
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "check_migration_branches.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("check_migration_branches", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


mod = _load_module()


def test_parse_heads_extracts_revision_ids() -> None:
    stdout = "\n".join(
        [
            "INFO  [alembic.runtime.migration] Context impl PostgresqlImpl.",
            "20261110_000009_merge_crm_enterprise_and_oa_letter_ocr_heads (head)",
            "6c00ee9fd217 (head) (mergepoint)",
            "",
        ]
    )
    assert mod.parse_heads(stdout) == [
        "20261110_000009_merge_crm_enterprise_and_oa_letter_ocr_heads",
        "6c00ee9fd217",
    ]


def test_ensure_single_head_is_noop_when_one_head(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(mod, "list_heads", lambda: ["only_head"])
    calls: list[list[str]] = []
    monkeypatch.setattr(mod, "run_alembic", lambda args: calls.append(args) or SimpleNamespace(returncode=0, stdout="", stderr=""))
    assert mod.ensure_single_head() == ["only_head"]
    assert calls == []


def test_ensure_single_head_merges_all_current_heads(monkeypatch: pytest.MonkeyPatch) -> None:
    states = [["aaa", "bbb", "ccc"], ["merged_head"]]

    def fake_list_heads() -> list[str]:
        return states.pop(0) if states else ["merged_head"]

    seen: list[list[str]] = []

    def fake_run(args: list[str]) -> subprocess.CompletedProcess[str]:
        seen.append(args)
        return subprocess.CompletedProcess(args, 0, "Generating merge.py ...  done\n", "")

    monkeypatch.setattr(mod, "list_heads", fake_list_heads)
    monkeypatch.setattr(mod, "run_alembic", fake_run)

    assert mod.ensure_single_head() == ["merged_head"]
    assert seen == [["merge", "-m", "auto_merge_alembic_heads", "aaa", "bbb", "ccc"]]


def test_main_upgrade_runs_after_merge(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(mod, "ensure_single_head", lambda: ["merged_head"])
    upgraded = {"ok": False}

    def fake_upgrade() -> None:
        upgraded["ok"] = True

    monkeypatch.setattr(mod, "upgrade_head", fake_upgrade)
    assert mod.main([]) == 0
    assert upgraded["ok"] is False
    assert mod.main(["--upgrade"]) == 0
    assert upgraded["ok"] is True


def test_main_returns_error_when_merge_fails(monkeypatch: pytest.MonkeyPatch) -> None:
    def boom() -> list[str]:
        raise RuntimeError("merge exploded")

    monkeypatch.setattr(mod, "ensure_single_head", boom)
    assert mod.main([]) == 1
