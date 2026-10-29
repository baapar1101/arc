"""Tenant-bound MCP tools for remaining user-facing domains."""
from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from app.services.ai.ai_function_extensions_mcp_club import (
    REPLACE_CUSTOMER_CLUB_TIERS_SCHEMA,
    replace_customer_club_tiers_handler,
)
from app.services.ai.ai_function_extensions_mcp_fiscal import (
    CREATE_FISCAL_YEAR_SCHEMA,
    create_fiscal_year_handler,
)
from app.services.ai.ai_function_extensions_mcp_freq import (
    CREATE_FREQUENT_DESCRIPTION_SCHEMA,
    create_frequent_description_handler,
)
from app.services.ai.ai_function_extensions_mcp_fx import (
    CREATE_CURRENCY_RATE_SCHEMA,
    create_currency_rate_handler,
)
from app.services.ai.ai_function_extensions_mcp_gei import (
    CREATE_GOODS_EXPENSE_INCOME_SCHEMA,
    create_goods_expense_income_handler,
)
from app.services.ai.ai_function_extensions_mcp_instances import (
    CREATE_PRODUCT_INSTANCE_SCHEMA,
    create_product_instance_handler,
    delete_product_instance_handler,
)
from app.services.ai.ai_function_extensions_mcp_loans import (
    CREATE_LOAN_FACILITY_SCHEMA,
    update_loan_facility_handler,
)
from app.services.ai.ai_function_extensions_mcp_notifications import (
    CREATE_BUSINESS_NOTIFICATION_TEMPLATE_SCHEMA,
    SEND_BUSINESS_NOTIFICATION_SCHEMA,
)
from app.services.ai.ai_function_extensions_mcp_quick_sales import (
    ENQUEUE_QUICK_SALE_SCHEMA,
    enqueue_quick_sale_handler,
)
from app.services.ai.ai_function_extensions_mcp_spec import CREATE_CATALOG_SPEC_FIELD_SCHEMA
from app.services.ai.ai_function_extensions_mcp_warehouse import (
    CREATE_WAREHOUSE_SCHEMA,
    create_warehouse_handler,
    delete_warehouse_handler,
)
from app.services.ai.ai_tool_catalog_quality import parse_registered_tool_fields
from app.services.ai.ai_tool_manifest import get_manifest_entry
from app.services.ai.ai_write_guard import is_write_function

REMAINING_TOOLS = (
    "get_available_product_instances",
    "create_product_instance",
    "update_product_instance",
    "delete_product_instance",
    "get_warehouse",
    "create_warehouse",
    "update_warehouse",
    "delete_warehouse",
    "create_warehouse_location",
    "update_warehouse_location",
    "delete_warehouse_location",
    "create_warehouse_placement",
    "update_warehouse_placement",
    "delete_warehouse_placement",
    "reconcile_warehouse_placements",
    "create_frequent_description",
    "update_frequent_description",
    "delete_frequent_description",
    "list_catalog_spec_fields",
    "get_catalog_spec_field",
    "create_catalog_spec_field",
    "update_catalog_spec_field",
    "delete_catalog_spec_field",
    "get_latest_currency_rates",
    "create_currency_rate",
    "update_currency_rate",
    "delete_currency_rate",
    "add_business_currency",
    "remove_business_currency",
    "create_loan_facility",
    "update_loan_facility",
    "delete_loan_facility",
    "regenerate_loan_schedule",
    "record_loan_payment",
    "delete_loan_payment",
    "create_fiscal_year",
    "update_current_fiscal_year",
    "set_current_fiscal_year",
    "preview_year_end_closing",
    "close_fiscal_year",
    "preview_fiscal_year_rollback",
    "execute_fiscal_year_rollback",
    "enqueue_quick_sale",
    "get_quick_sale_job",
    "update_quick_sales_settings",
    "list_quick_sales_payment_buttons",
    "create_quick_sales_payment_button",
    "update_quick_sales_payment_button",
    "delete_quick_sales_payment_button",
    "reorder_quick_sales_payment_buttons",
    "list_quick_sales_stock_discrepancies",
    "create_quick_sales_stock_correction",
    "replace_customer_club_tiers",
    "list_customer_club_rewards",
    "save_customer_club_reward",
    "redeem_customer_club_reward",
    "list_customer_club_vouchers",
    "set_customer_club_consent",
    "submit_customer_club_survey",
    "get_customer_club_member_profile",
    "preview_customer_club_segment",
    "list_customer_club_campaigns",
    "save_customer_club_campaign",
    "run_customer_club_campaign",
    "get_customer_club_campaign_stats",
    "get_business_notification_template",
    "create_business_notification_template",
    "update_business_notification_template",
    "submit_business_notification_template",
    "preview_business_notification_template",
    "send_business_notification",
    "get_goods_expense_income_settings",
    "list_goods_expense_income",
    "get_goods_expense_income",
    "create_goods_expense_income",
    "update_goods_expense_income",
    "submit_goods_expense_income",
    "allocate_goods_expense_income",
    "post_goods_expense_income",
    "cancel_goods_expense_income",
    "delete_goods_expense_income",
)
ALWAYS_CONFIRM = (
    "delete_product_instance",
    "delete_warehouse",
    "delete_warehouse_location",
    "delete_warehouse_placement",
    "delete_frequent_description",
    "delete_catalog_spec_field",
    "delete_currency_rate",
    "remove_business_currency",
    "delete_loan_facility",
    "regenerate_loan_schedule",
    "record_loan_payment",
    "delete_loan_payment",
    "set_current_fiscal_year",
    "close_fiscal_year",
    "execute_fiscal_year_rollback",
    "enqueue_quick_sale",
    "delete_quick_sales_payment_button",
    "create_quick_sales_stock_correction",
    "replace_customer_club_tiers",
    "redeem_customer_club_reward",
    "run_customer_club_campaign",
    "send_business_notification",
    "post_goods_expense_income",
    "cancel_goods_expense_income",
    "delete_goods_expense_income",
)
READONLY = (
    "get_available_product_instances",
    "get_warehouse",
    "reconcile_warehouse_placements",
    "list_catalog_spec_fields",
    "get_catalog_spec_field",
    "get_latest_currency_rates",
    "preview_year_end_closing",
    "preview_fiscal_year_rollback",
    "get_quick_sale_job",
    "list_quick_sales_payment_buttons",
    "list_quick_sales_stock_discrepancies",
    "list_customer_club_rewards",
    "list_customer_club_vouchers",
    "get_customer_club_member_profile",
    "preview_customer_club_segment",
    "list_customer_club_campaigns",
    "get_customer_club_campaign_stats",
    "get_business_notification_template",
    "preview_business_notification_template",
    "get_goods_expense_income_settings",
    "list_goods_expense_income",
    "get_goods_expense_income",
)
CAPABILITIES = {
    "create_product_instance": "inventory.stock",
    "create_warehouse": "inventory.warehouse",
    "create_frequent_description": "financial.document",
    "create_catalog_spec_field": "inventory.product",
    "create_currency_rate": "financial.currency",
    "create_loan_facility": "financial.loan",
    "create_fiscal_year": "financial.fiscal",
    "enqueue_quick_sale": "financial.invoice",
    "save_customer_club_reward": "customer_club.loyalty",
    "create_business_notification_template": "platform.notifications",
    "create_goods_expense_income": "inventory.warehouse",
}


def _ctx(*, business_id: int = 7, user_id: int = 9, db=None):
    user = MagicMock()
    user.get_user_id.return_value = user_id
    return {
        "db": db if db is not None else MagicMock(),
        "business_id": business_id,
        "user_context": user,
    }


def _assert_no_extra_blob(schema: dict) -> None:
    assert schema.get("additionalProperties") is False
    props = schema.get("properties") or {}
    assert "extra_info" not in props
    assert "business_id" not in props


def test_remaining_tools_are_registered_with_strict_schemas():
    parsed = parse_registered_tool_fields()
    for name in REMAINING_TOOLS:
        assert name in parsed, name
        fields = parsed[name]
        if name in READONLY:
            assert fields["is_readonly"] is True
            assert fields["requires_approval"] is False
        else:
            assert fields["requires_approval"] is True
            assert fields["is_readonly"] is False

    assert parsed["create_product_instance"]["required_permissions"] == ["inventory.write"]
    assert parsed["delete_product_instance"]["risk_level"] == "high"
    assert parsed["create_warehouse"]["required_permissions"] == ["warehouses.write"]
    assert parsed["delete_warehouse"]["required_permissions"] == ["warehouses.delete"]
    assert parsed["create_loan_facility"]["required_permissions"] == ["loan_facilities.write"]
    assert parsed["close_fiscal_year"]["required_permissions"] == ["fiscal_years.close"]
    assert parsed["close_fiscal_year"]["risk_level"] == "high"
    assert parsed["enqueue_quick_sale"]["risk_level"] == "high"
    assert parsed["send_business_notification"]["required_permissions"] == ["notifications.send"]
    assert parsed["post_goods_expense_income"]["required_permissions"] == ["goods_expense_income.post"]
    assert CREATE_PRODUCT_INSTANCE_SCHEMA["required"] == ["product_id", "serial_number"]
    assert CREATE_WAREHOUSE_SCHEMA["required"] == ["name"]
    assert CREATE_FREQUENT_DESCRIPTION_SCHEMA["required"] == ["text"]
    assert CREATE_CATALOG_SPEC_FIELD_SCHEMA["required"] == ["title"]
    assert CREATE_CURRENCY_RATE_SCHEMA["properties"]["rate"]["exclusiveMinimum"] == 0
    assert CREATE_LOAN_FACILITY_SCHEMA["required"] == [
        "title",
        "currency_id",
        "principal_amount",
        "contract_date",
    ]
    assert CREATE_FISCAL_YEAR_SCHEMA["required"] == ["title", "start_date", "end_date"]
    assert ENQUEUE_QUICK_SALE_SCHEMA["required"] == ["request_id", "lines"]
    assert "extra_info" not in ENQUEUE_QUICK_SALE_SCHEMA["properties"]
    assert REPLACE_CUSTOMER_CLUB_TIERS_SCHEMA["required"] == ["tiers"]
    assert CREATE_BUSINESS_NOTIFICATION_TEMPLATE_SCHEMA["required"] == [
        "code",
        "name",
        "event_type",
        "channel",
        "body",
    ]
    assert CREATE_GOODS_EXPENSE_INCOME_SCHEMA["required"] == ["doc_kind", "document_date", "lines"]
    for schema in (
        CREATE_PRODUCT_INSTANCE_SCHEMA,
        CREATE_WAREHOUSE_SCHEMA,
        CREATE_FREQUENT_DESCRIPTION_SCHEMA,
        CREATE_CATALOG_SPEC_FIELD_SCHEMA,
        CREATE_CURRENCY_RATE_SCHEMA,
        CREATE_LOAN_FACILITY_SCHEMA,
        CREATE_FISCAL_YEAR_SCHEMA,
        ENQUEUE_QUICK_SALE_SCHEMA,
        REPLACE_CUSTOMER_CLUB_TIERS_SCHEMA,
        CREATE_BUSINESS_NOTIFICATION_TEMPLATE_SCHEMA,
        SEND_BUSINESS_NOTIFICATION_SCHEMA,
        CREATE_GOODS_EXPENSE_INCOME_SCHEMA,
    ):
        _assert_no_extra_blob(schema)


def test_remaining_manifest_capabilities_and_confirm():
    for name in REMAINING_TOOLS:
        entry = get_manifest_entry(name)
        assert entry is not None, name
        if name in READONLY:
            assert entry.intent_write is False
        else:
            assert entry.intent_write is True
    for name in ALWAYS_CONFIRM:
        entry = get_manifest_entry(name)
        assert entry is not None and entry.always_confirm is True and entry.intent_write is True, name
    for name, cap in CAPABILITIES.items():
        assert get_manifest_entry(name).capability == cap
    assert get_manifest_entry("delete_warehouse").side_effect == "delete"
    assert get_manifest_entry("close_fiscal_year").always_confirm is True
    assert "create_product_instance" in (get_manifest_entry("search_product_instances").companion_tools or ())
    assert "create_warehouse" in (get_manifest_entry("list_warehouses").companion_tools or ())
    assert is_write_function("create_product_instance") is True
    assert is_write_function("get_available_product_instances") is False
    assert is_write_function("enqueue_quick_sale") is True


def test_instance_create_pins_tenant_and_omits_extra():
    db = MagicMock()
    product = MagicMock(id=3)
    db.query.return_value.filter.return_value.first.side_effect = [product, None]
    with patch(
        "app.services.product_attribute_service.validate_custom_attributes",
        return_value=(True, None),
    ):
        out = create_product_instance_handler(
            {
                "product_id": 3,
                "serial_number": "SN-1",
                "business_id": 99,
                "extra_info": {"x": 1},
            },
            _ctx(db=db),
        )
    assert out["serial_number"] == "SN-1"
    added = db.add.call_args[0][0]
    assert added.business_id == 7


def test_instance_delete_rejects_sold():
    inst = MagicMock(status="sold", business_id=7)
    db = MagicMock()
    db.query.return_value.filter.return_value.first.return_value = inst
    with pytest.raises(ValueError, match="فروخته"):
        delete_product_instance_handler({"instance_id": 4}, _ctx(db=db))


def test_warehouse_create_uses_tenant_service():
    with patch(
        "app.services.warehouse_service.create_warehouse",
        return_value={"data": {"id": 2, "name": "اصلی"}},
    ) as create:
        out = create_warehouse_handler(
            {"name": "اصلی", "business_id": 99, "extra_info": {"x": 1}},
            _ctx(),
        )
    assert out["id"] == 2
    assert create.call_args.args[1] == 7


def test_warehouse_delete_missing_raises():
    with patch("app.services.warehouse_service.delete_warehouse", return_value=False):
        with pytest.raises(ValueError, match="انبار"):
            delete_warehouse_handler({"warehouse_id": 8}, _ctx())


def test_frequent_description_commits_after_flush():
    row = MagicMock()
    db = MagicMock()
    with patch(
        "app.services.business_frequent_description_service.create_row",
        return_value=row,
    ), patch(
        "app.services.business_frequent_description_service.to_dict",
        return_value={"id": 1, "text": "بابت فروش"},
    ):
        out = create_frequent_description_handler({"text": "بابت فروش", "business_id": 99}, _ctx(db=db))
    assert out["text"] == "بابت فروش"
    db.commit.assert_called()


def test_currency_rate_omits_extra_and_pins_tenant():
    with patch(
        "app.services.business_currency_rate_service.create_business_currency_rate",
        return_value={"id": 5, "rate": 1.2},
    ) as create:
        out = create_currency_rate_handler(
            {
                "currency_id": 2,
                "effective_at": "2026-01-01T00:00:00Z",
                "rate": 1.2,
                "extra_info": {"x": 1},
                "business_id": 99,
            },
            _ctx(),
        )
    assert out["id"] == 5
    assert create.call_args.args[1] == 7
    assert "extra_info" not in create.call_args.args[3]


def test_loan_update_pins_tenant_before_service():
    with patch(
        "app.services.received_loan_facility_service.get_facility_by_id",
        return_value={"id": 3, "business_id": 7},
    ), patch(
        "app.services.received_loan_facility_service.update_facility",
        return_value={"id": 3, "business_id": 7, "title": "وام"},
    ) as update:
        out = update_loan_facility_handler({"facility_id": 3, "title": "وام", "business_id": 99}, _ctx())
    assert out["title"] == "وام"
    update.assert_called_once()


def test_loan_update_rejects_other_tenant():
    with patch(
        "app.services.received_loan_facility_service.get_facility_by_id",
        return_value={"id": 3, "business_id": 8},
    ):
        with pytest.raises(ValueError, match="تسهیل"):
            update_loan_facility_handler({"facility_id": 3, "title": "وام"}, _ctx())


def test_fiscal_create_rejects_overlap():
    other = MagicMock(title="۱۴۰۴", start_date=__import__("datetime").date(2026, 1, 1), end_date=__import__("datetime").date(2026, 12, 31), is_last=True)
    repo = MagicMock()
    repo.list_by_business.return_value = [other]
    with patch("adapters.db.repositories.fiscal_year_repo.FiscalYearRepository", return_value=repo):
        with pytest.raises(ValueError, match="همپوشانی"):
            create_fiscal_year_handler(
                {"title": "تکراری", "start_date": "2026-06-01", "end_date": "2026-12-01"},
                _ctx(),
            )


def test_enqueue_quick_sale_builds_extra_info_internally():
    job = MagicMock()
    with patch(
        "app.services.quick_sale_invoice_job_service.enqueue_quick_sale_invoice",
        return_value=job,
    ) as enqueue, patch(
        "app.services.quick_sale_invoice_job_service.serialize_quick_sale_job",
        return_value={"request_id": "qs-1234567890abcd", "status": "queued"},
    ), patch(
        "app.core.permissions.user_can_change_invoice_unit_price",
        return_value=False,
    ):
        out = enqueue_quick_sale_handler(
            {
                "request_id": "qs-1234567890abcd",
                "lines": [{"product_id": 1, "quantity": 2}],
                "extra_info": {"injected": True},
                "business_id": 99,
            },
            _ctx(),
        )
    payload = enqueue.call_args.kwargs["payload"]
    assert payload["invoice_type"] == "invoice_sales"
    assert payload["extra_info"]["quick_sale"] is True
    assert payload["extra_info"]["quick_sale_request_id"] == "qs-1234567890abcd"
    assert "injected" not in payload["extra_info"]
    assert out["status"] == "queued"


def test_club_replace_tiers_requires_plugin():
    with patch(
        "app.core.customer_club_plugin_dependency.check_customer_club_plugin_active",
        return_value=False,
    ):
        with pytest.raises(ValueError, match="افزونه"):
            replace_customer_club_tiers_handler({"tiers": []}, _ctx())


def test_gei_create_omits_extra_and_pins_tenant():
    with patch(
        "app.services.goods_expense_income_service.create_document",
        return_value={"id": 9, "doc_kind": "goods_expense"},
    ) as create:
        out = create_goods_expense_income_handler(
            {
                "doc_kind": "goods_expense",
                "document_date": "2026-01-02",
                "lines": [{"product_id": 1, "warehouse_id": 2, "quantity": 1}],
                "extra_info": {"x": 1},
                "business_id": 99,
            },
            _ctx(),
        )
    assert out["id"] == 9
    assert create.call_args.args[1] == 7
    assert "extra_info" not in create.call_args.args[3]
