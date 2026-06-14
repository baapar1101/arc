"""Unit tests for AI skill parser (agentskills.io subset)."""
from __future__ import annotations

import io
import zipfile

import pytest

from app.services.ai.ai_skill_parser import (
    compose_skill_md,
    extract_skill_from_zip,
    parse_skill_md,
    validate_skill_slug,
)


def test_validate_skill_slug():
    assert validate_skill_slug("debt-analysis") is None
    assert validate_skill_slug("PDF") == "SKILL_SLUG_FORMAT_INVALID"
    assert validate_skill_slug("-bad") == "SKILL_SLUG_FORMAT_INVALID"


def test_parse_skill_md_minimal():
    md = compose_skill_md(
        skill_slug="sales-report",
        description="Weekly sales summary. Use when user asks about weekly sales.",
        skill_body="## Steps\n1. Run get_sales_report",
        allowed_tool_names=["get_sales_report"],
    )
    parsed = parse_skill_md(md)
    assert parsed.skill_slug == "sales-report"
    assert "weekly sales" in parsed.description.lower()
    assert parsed.allowed_tool_names == ["get_sales_report"]
    assert "get_sales_report" in parsed.skill_body


def test_extract_skill_from_zip():
    buf = io.BytesIO()
    skill_md = compose_skill_md(
        skill_slug="zip-test",
        description="Test zip import skill for unit tests.",
        skill_body="# Hello",
    )
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("zip-test/SKILL.md", skill_md)
        zf.writestr("zip-test/references/extra.md", "more info")
    parsed = extract_skill_from_zip(buf.getvalue())
    assert parsed.skill_slug == "zip-test"
    assert parsed.has_references
    assert "references/extra.md" in parsed.bundle_files
