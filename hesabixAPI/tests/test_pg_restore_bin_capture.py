"""Verify deploy.sh captures a valid pg_restore executable path only.

Tests extract and execute the small shell resolver in isolation. They do not
source deploy.sh, install packages, read a database, or restore a dump.
"""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "deploy.sh"


def _function(source: str, name: str) -> str:
    pattern = rf"(?ms)^{re.escape(name)}\(\) \{{\n.*?^\}}\n"
    match = re.search(pattern, source)
    assert match is not None, f"Cannot extract {name}"
    return match.group(0)


@pytest.fixture
def helper():
    return _function(SCRIPT.read_text(encoding="utf-8"), "hesabix_pg_restore_bin_for_dump")


def _resolve(helper: str, raw: str) -> subprocess.CompletedProcess[str]:
    command = (
        'hesabix_resolve_pg_restore_for_dump() { printf "%s" "$MOCK_RAW"; }\n'
        + helper
        + "\nhesabix_pg_restore_bin_for_dump fake-dump\n"
    )
    env = os.environ.copy()
    env["MOCK_RAW"] = raw
    return subprocess.run(["bash", "-c", command], env=env, capture_output=True, text=True)


def test_direct_executable_path_preserved(helper, tmp_path):
    binary = tmp_path / "pg_restore"
    binary.write_text("#!/bin/sh\nexit 0\n")
    binary.chmod(0o700)
    result = _resolve(helper, str(binary))
    assert result.returncode == 0
    assert result.stdout == str(binary)


def test_old_stdout_log_does_not_contaminate_executable_path(helper, tmp_path):
    binary = tmp_path / "pg_restore"
    binary.write_text("#!/bin/sh\nexit 0\n")
    binary.chmod(0o700)
    result = _resolve(helper, f"checking client version...\n{binary}")
    assert result.returncode == 0
    assert result.stdout == str(binary)


def test_last_valid_executable_wins(helper, tmp_path):
    older, newer = tmp_path / "old-pg_restore", tmp_path / "new-pg_restore"
    for path in (older, newer):
        path.write_text("#!/bin/sh\nexit 0\n")
        path.chmod(0o700)
    result = _resolve(helper, f"progress message\n{older}\n{newer}")
    assert result.returncode == 0
    assert result.stdout == str(newer)


def test_non_executable_output_fails_closed(helper, tmp_path):
    binary = tmp_path / "not-executable"
    binary.write_text("not an executable")
    result = _resolve(helper, f"progress message\n{binary}")
    assert result.returncode != 0
    assert result.stdout == ""


def test_upstream_resolver_status_messages_use_stderr():
    source = SCRIPT.read_text(encoding="utf-8")
    original = _function(source, "hesabix_resolve_pg_restore_for_dump")
    for line in original.splitlines():
        if 'log_info "' in line or 'log_warning "' in line or "hesabix_ensure_postgresql_client_major " in line:
            assert ">&2" in line, f"status leaked to stdout: {line}"
    assert 'pg_restore_bin=$(hesabix_pg_restore_bin_for_dump "${dump}" || true)' in source
    assert 'pg_restore_bin=$(hesabix_pg_restore_bin_for_dump "${seed_dump}" || true)' in source
