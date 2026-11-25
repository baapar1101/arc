#!/usr/bin/env python3
"""Ensure Alembic has a single head, then optionally run upgrade.

When two developers add migrations from the same parent, Alembic grows
multiple heads and `alembic upgrade head` refuses to start the API.
This script merges every current head into one empty revision so the
next upgrade can run. Safe to call on every deploy/start: one head is a no-op.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ALEMBIC_INI = PROJECT_ROOT / "alembic.ini"
MAX_MERGE_ROUNDS = 5


def parse_heads(stdout: str) -> list[str]:
    """Extract revision ids from `alembic heads` output."""
    heads: list[str] = []
    for raw in stdout.splitlines():
        line = raw.strip()
        if not line or line.startswith(("INFO", "DEBUG", "WARNING", "ERROR")):
            continue
        token = line.split()[0]
        if token:
            heads.append(token)
    return heads


def _alembic_env() -> dict[str, str]:
    env = os.environ.copy()
    existing = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = (
        str(PROJECT_ROOT) if not existing else f"{PROJECT_ROOT}{os.pathsep}{existing}"
    )
    return env


def run_alembic(args: list[str]) -> subprocess.CompletedProcess[str]:
    cmd = [sys.executable, "-m", "alembic", "-c", str(ALEMBIC_INI), *args]
    return subprocess.run(
        cmd,
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=False,
        env=_alembic_env(),
    )


def list_heads() -> list[str]:
    result = run_alembic(["heads"])
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "alembic heads failed").strip()
        raise RuntimeError(detail)
    return parse_heads(result.stdout)


def ensure_single_head() -> list[str]:
    """Merge until Alembic reports one head. Returns the remaining heads."""
    heads = list_heads()
    if len(heads) <= 1:
        return heads

    for round_i in range(1, MAX_MERGE_ROUNDS + 1):
        print(
            f"alembic: {len(heads)} heads; auto-merging (round {round_i}): {', '.join(heads)}",
            flush=True,
        )
        result = run_alembic(["merge", "-m", "auto_merge_alembic_heads", *heads])
        if result.stdout.strip():
            print(result.stdout.strip(), flush=True)
        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "alembic merge failed").strip()
            raise RuntimeError(detail)
        heads = list_heads()
        if len(heads) <= 1:
            return heads

    raise RuntimeError(
        f"still {len(heads)} heads after {MAX_MERGE_ROUNDS} merges: {', '.join(heads)}"
    )


def upgrade_head() -> None:
    result = run_alembic(["upgrade", "head"])
    if result.stderr:
        sys.stderr.write(result.stderr)
    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.returncode != 0:
        raise RuntimeError((result.stderr or result.stdout or "alembic upgrade head failed").strip())


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Merge multiple Alembic heads, then optionally upgrade."
    )
    parser.add_argument(
        "--upgrade",
        action="store_true",
        help="Run `alembic upgrade head` after heads are merged.",
    )
    args = parser.parse_args(argv)
    try:
        heads = ensure_single_head()
        if not heads:
            print("alembic: no heads found", file=sys.stderr)
            return 1
        print(f"alembic: single head {heads[0]}", flush=True)
        if args.upgrade:
            upgrade_head()
        return 0
    except RuntimeError as exc:
        print(f"alembic: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
