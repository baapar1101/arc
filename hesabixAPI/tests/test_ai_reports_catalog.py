"""تست کاتالوگ گزارش AI."""
from __future__ import annotations

from unittest.mock import MagicMock

from app.services.ai.ai_reports_catalog import REPORT_TYPES, get_report_definition
from app.services.ai.ai_reports_service import list_available_reports


def test_report_types_include_trial_balance():
    assert "trial_balance" in REPORT_TYPES
    assert "basalam_overview" in REPORT_TYPES


def test_general_ledger_requires_accounts():
    d = get_report_definition("general_ledger")
    assert d is not None
    assert "account_ids" in d.requires


def test_list_available_reports_respects_permission():
    ctx = MagicMock()
    ctx.is_superadmin.return_value = False
    ctx.is_business_owner.return_value = True
    ctx.business_id = 1
    out = list_available_reports(ctx, business_id=1)
    assert out["total"] >= len(REPORT_TYPES) - 5
