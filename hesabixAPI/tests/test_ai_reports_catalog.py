"""تست کاتالوگ گزارش AI و تطبیق با منوی گزارشات."""
from __future__ import annotations

from unittest.mock import MagicMock, patch

from app.services.ai.ai_reports_catalog import (
    PLUGIN_GATED_REPORT_TYPES,
    REPORT_DEFINITIONS,
    REPORT_TYPES,
    UI_MENU_REPORT_KEYS,
    get_report_definition,
    report_definitions_for_ui_key,
)
from app.services.ai.ai_reports_service import execute_ai_report, list_available_reports, plugin_is_active


def _owner_ctx() -> MagicMock:
    ctx = MagicMock()
    ctx.is_superadmin.return_value = False
    ctx.is_business_owner.return_value = True
    ctx.business_id = 1
    return ctx


def test_report_types_include_trial_balance():
    assert "trial_balance" in REPORT_TYPES


def test_report_types_include_balance_sheet():
    assert "balance_sheet" in REPORT_TYPES
    assert "basalam_overview" in REPORT_TYPES


def test_sprint1_report_types_are_registered():
    for name in (
        "installments",
        "ar_aging",
        "ap_aging",
        "person_balances_by_currency",
        "checks",
        "stock_count",
        "financial_package",
        "cash_flow_statement",
        "fx_revaluation",
        "woocommerce_overview",
        "woocommerce_orders",
        "woocommerce_catalog",
        "woocommerce_bridge",
        "kardex",
        "activity_logs",
        "hscript_reports",
        "basalam_overview",
        "basalam_synced_invoices",
        "basalam_dead_letter",
        "basalam_product_conflicts",
    ):
        assert get_report_definition(name) is not None, name


def test_report_types_are_unique():
    types = [d.report_type for d in REPORT_DEFINITIONS]
    assert len(types) == len(set(types))


def test_general_ledger_requires_accounts():
    d = get_report_definition("general_ledger")
    assert d is not None
    assert "account_ids" in d.requires


def test_ui_menu_keys_have_catalog_equivalents():
    missing = [key for key in UI_MENU_REPORT_KEYS if not report_definitions_for_ui_key(key)]
    assert missing == []


def test_cash_flow_ui_key_maps_to_statement():
    defs = report_definitions_for_ui_key("cash_flow")
    assert any(d.report_type == "cash_flow_statement" for d in defs)


def test_plugin_gated_types_match_definitions():
    assert set(PLUGIN_GATED_REPORT_TYPES) == {
        d.report_type for d in REPORT_DEFINITIONS if d.plugin_code
    }
    assert "woocommerce_overview" in PLUGIN_GATED_REPORT_TYPES
    assert "distribution_dashboard" in PLUGIN_GATED_REPORT_TYPES
    assert "trial_balance" not in PLUGIN_GATED_REPORT_TYPES


def test_list_available_reports_excludes_plugins_without_db():
    out = list_available_reports(_owner_ctx(), business_id=1)
    types = {item["report_type"] for item in out["items"]}
    assert types.isdisjoint(PLUGIN_GATED_REPORT_TYPES)
    assert out["total"] == len(REPORT_TYPES) - len(PLUGIN_GATED_REPORT_TYPES)
    assert "system" in out["categories"]


def test_list_available_reports_includes_active_plugin():
    ctx = _owner_ctx()
    db = MagicMock()
    with patch("app.services.ai.ai_reports_service.plugin_is_active", side_effect=lambda _db, _bid, code: code == "woocommerce_hesabix"):
        out = list_available_reports(ctx, business_id=1, db=db)
    types = {item["report_type"] for item in out["items"]}
    assert "woocommerce_overview" in types
    assert "basalam_overview" not in types
    assert "distribution_dashboard" not in types


def test_list_available_reports_category_filter():
    out = list_available_reports(_owner_ctx(), business_id=1, category="accounting")
    assert out["items"]
    assert all(item["category"] == "accounting" for item in out["items"])
    assert "cash_flow_statement" in {item["report_type"] for item in out["items"]}


def test_list_available_reports_respects_permission():
    ctx = MagicMock()
    ctx.is_superadmin.return_value = False
    ctx.is_business_owner.return_value = False
    ctx.business_id = 1
    ctx.has_app_permission.return_value = False
    ctx.has_business_permission.side_effect = (
        lambda section, action: section == "accounting_documents" and action == "view"
    )
    out = list_available_reports(ctx, business_id=1)
    types = {item["report_type"] for item in out["items"]}
    assert "trial_balance" in types
    assert "activity_logs" not in types
    assert types.isdisjoint(PLUGIN_GATED_REPORT_TYPES)


def test_plugin_is_active_fail_closed_without_db():
    assert plugin_is_active(None, 1, "woocommerce_hesabix") is False
    assert plugin_is_active(None, 1, None) is True
    assert plugin_is_active(MagicMock(), 1, "unknown_plugin") is False


def test_execute_unknown_report_type():
    try:
        execute_ai_report(MagicMock(), 1, "not_a_report", {})
        raise AssertionError("expected ValueError")
    except ValueError as exc:
        assert "نامعتبر" in str(exc)


def test_execute_general_ledger_requires_account_ids():
    try:
        execute_ai_report(MagicMock(), 1, "general_ledger", {})
        raise AssertionError("expected ValueError")
    except ValueError as exc:
        assert "account_ids" in str(exc)


def test_execute_plugin_inactive():
    with patch("app.services.ai.ai_reports_service.plugin_is_active", return_value=False):
        try:
            execute_ai_report(MagicMock(), 1, "woocommerce_overview", {})
            raise AssertionError("expected ValueError")
        except ValueError as exc:
            assert "افزونه" in str(exc)


def test_execute_permission_denied():
    ctx = MagicMock()
    ctx.is_superadmin.return_value = False
    ctx.is_business_owner.return_value = False
    ctx.has_app_permission.return_value = False
    ctx.has_business_permission.return_value = False
    try:
        execute_ai_report(MagicMock(), 1, "trial_balance", {}, user_context=ctx)
        raise AssertionError("expected ValueError")
    except ValueError as exc:
        assert "مجوز" in str(exc)


def test_execute_installments_dispatches():
    with patch("app.services.invoice_service.search_installments", return_value={"items": []}) as fn:
        out = execute_ai_report(MagicMock(), 7, "installments", {"from_date": "2026-01-01", "to_date": "2026-01-31"})
    assert out == {"items": []}
    query = fn.call_args.args[2]
    assert query["due_from"] == "2026-01-01"
    assert query["due_to"] == "2026-01-31"


def test_execute_ar_and_ap_aging_dispatches():
    with patch("app.services.ar_ap_aging_service.get_ar_ap_aging_report", return_value={"mode": "ar"}) as fn:
        execute_ai_report(MagicMock(), 1, "ar_aging", {"as_of_date": "2026-03-20"})
        execute_ai_report(MagicMock(), 1, "ap_aging", {})
    modes = [call.kwargs["mode"] for call in fn.call_args_list]
    assert modes == ["ar", "ap"]
    assert fn.call_args_list[0].kwargs["as_of"] == "2026-03-20"


def test_execute_person_balances_and_checks():
    with patch(
        "app.services.person_balances_by_currency_report_service.get_person_balances_by_currency_report",
        return_value={"items": [1]},
    ) as balances:
        assert execute_ai_report(MagicMock(), 1, "person_balances_by_currency", {}) == {"items": [1]}
        assert balances.called
    with patch("app.services.check_service.list_checks", return_value={"items": []}) as checks:
        execute_ai_report(MagicMock(), 1, "checks", {"check_type": "receivable", "from_date": "2026-01-01"})
        query = checks.call_args.args[2]
        assert any(f.get("property") == "type" and f.get("value") == "RECEIVABLE" for f in query["filters"])


def test_execute_cash_flow_keeps_receipts_and_statement_is_separate():
    with patch("app.services.receipt_payment_service.list_receipts_payments", return_value={"items": []}):
        out = execute_ai_report(MagicMock(), 1, "cash_flow", {})
    assert "net_cash_flow" in out
    with patch("app.services.cash_flow_report_service.get_cash_flow_report", return_value={"statement": True}) as fn:
        assert execute_ai_report(MagicMock(), 1, "cash_flow_statement", {"include_indirect": False}) == {"statement": True}
        assert fn.call_args.kwargs["include_indirect"] is False


def test_execute_financial_package_and_fx_and_kardex():
    with patch("app.services.financial_package_service.get_financial_package_report", return_value={"ok": 1}) as pkg:
        execute_ai_report(MagicMock(), 1, "financial_package", {"account_level": 3})
        assert pkg.call_args.kwargs["account_level"] == 3
    with patch("app.services.cash_flow_report_service.get_fx_revaluation_report", return_value={"items": []}) as fx:
        execute_ai_report(MagicMock(), 1, "fx_revaluation", {})
        assert fx.called
    with patch("app.services.kardex_service.list_kardex_lines", return_value={"items": []}) as kardex:
        execute_ai_report(MagicMock(), 1, "kardex", {"account_ids": [9]})
        assert kardex.call_args.args[2]["account_ids"] == [9]


def test_execute_activity_logs_and_hscript():
    with patch(
        "app.services.ai.ai_reports_service._search_activity_logs_for_report",
        return_value={"items": []},
    ) as logs:
        execute_ai_report(MagicMock(), 1, "activity_logs", {"log_category": "invoice"})
        assert logs.call_args.args[2]["category"] == "invoice"
    with patch("app.services.hscript_report_service.list_reports", return_value={"items": []}) as hs:
        execute_ai_report(MagicMock(), 1, "hscript_reports", {"status": "published"})
        assert hs.call_args.kwargs["status"] == "published"


def test_execute_woocommerce_reports():
    with patch("app.services.ai.ai_reports_service.plugin_is_active", return_value=True):
        with patch("app.services.woocommerce_integration_service.reports_summary", return_value={"sum": 1}) as summary:
            execute_ai_report(MagicMock(), 1, "woocommerce_overview", {"from_date": "2026-01-01"})
            assert summary.call_args.kwargs["after"] == "2026-01-01"
        with patch("app.services.woocommerce_integration_service.list_orders", return_value={"items": []}) as orders:
            execute_ai_report(MagicMock(), 1, "woocommerce_orders", {"take": 10, "skip": 10})
            assert orders.call_args.kwargs["page"] == 2
        with patch("app.services.woocommerce_integration_service.list_products", return_value={"items": []}) as products:
            execute_ai_report(MagicMock(), 1, "woocommerce_catalog", {"search": "shirt"})
            assert products.call_args.kwargs["search"] == "shirt"
        with patch("app.services.woocommerce_integration_service.control_connection", return_value={"ok": True}):
            with patch("app.services.woocommerce_integration_service.control_sync_stats", return_value={"n": 3}):
                out = execute_ai_report(MagicMock(), 1, "woocommerce_bridge", {})
        assert out["connection"]["ok"] is True
        assert out["sync_stats"]["n"] == 3
