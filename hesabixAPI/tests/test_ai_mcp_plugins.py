"""Tenant-bound MCP tools for remaining plugins and business settings."""
from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from app.core.responses import ApiError
from app.services.ai.ai_function_extensions_mcp_barcode import (
    UPDATE_BARCODE_PRINTER_SETTINGS_SCHEMA,
    create_barcode_label_from_preset_handler,
    list_barcode_label_templates_handler,
    update_barcode_label_printer_settings_handler,
)
from app.services.ai.ai_function_extensions_mcp_fixed_assets import (
    CAPITALIZE_FIXED_ASSET_SCHEMA,
    CREATE_FIXED_ASSET_SCHEMA,
    DISPOSE_FIXED_ASSET_SCHEMA,
    GET_FIXED_ASSET_REPORT_SCHEMA,
    LIST_FIXED_ASSETS_SCHEMA,
    UPDATE_FIXED_ASSET_SETTINGS_SCHEMA,
    capitalize_fixed_asset_handler,
    create_fixed_asset_handler,
    delete_fixed_asset_handler,
    get_fixed_asset_settings_handler,
    list_fixed_assets_handler,
    update_fixed_asset_settings_handler,
)
from app.services.ai.ai_function_extensions_mcp_settings import (
    UPDATE_BUSINESS_INFO_SCHEMA,
    UPDATE_DOCUMENT_NUMBERING_SCHEMA,
    update_business_info_handler,
    update_document_numbering_settings_handler,
)
from app.services.ai.ai_function_extensions_mcp_telephony import (
    CLICK_TO_CALL_SCHEMA,
    UPDATE_TELEPHONY_SETTINGS_SCHEMA,
    click_to_call_handler,
    get_telephony_dashboard_handler,
    get_telephony_settings_handler,
    list_telephony_pbx_handler,
    update_telephony_settings_handler,
)
from app.services.ai.ai_tool_catalog_quality import parse_registered_tool_fields
from app.services.ai.ai_tool_manifest import get_manifest_entry
from app.services.ai.ai_write_guard import is_write_function

FIXED_ASSET_TOOLS = (
    "get_fixed_asset_settings",
    "update_fixed_asset_settings",
    "get_fixed_assets_dashboard",
    "list_fixed_asset_classes",
    "update_fixed_asset_class",
    "list_fixed_asset_locations",
    "create_fixed_asset_location",
    "update_fixed_asset_location",
    "list_fixed_assets",
    "get_fixed_asset",
    "create_fixed_asset",
    "update_fixed_asset",
    "delete_fixed_asset",
    "capitalize_fixed_asset",
    "set_fixed_asset_idle",
    "resume_fixed_asset",
    "dispose_fixed_asset",
    "post_fixed_asset_expenditure",
    "change_fixed_asset_estimate",
    "list_fixed_asset_depreciation_runs",
    "get_fixed_asset_depreciation_run",
    "create_fixed_asset_depreciation_run",
    "post_fixed_asset_depreciation_run",
    "delete_fixed_asset_depreciation_run",
    "get_fixed_asset_report",
)
TELEPHONY_TOOLS = (
    "get_telephony_settings",
    "update_telephony_settings",
    "get_telephony_dashboard",
    "list_telephony_pbx",
    "update_telephony_pbx",
    "list_telephony_extensions",
    "upsert_telephony_extension",
    "list_telephony_user_extensions",
    "upsert_telephony_user_extension",
    "delete_telephony_user_extension",
    "list_telephony_calls",
    "get_telephony_call",
    "update_telephony_call",
    "create_person_from_telephony_call",
    "create_lead_from_telephony_call",
    "click_to_call",
    "lookup_telephony_number",
    "get_telephony_reports_summary",
)
BARCODE_TOOLS = (
    "list_barcode_label_templates",
    "get_barcode_label_template",
    "get_default_barcode_label_template",
    "set_default_barcode_label_template",
    "create_barcode_label_from_preset",
    "publish_barcode_label_template",
    "archive_barcode_label_template",
    "duplicate_barcode_label_template",
    "list_barcode_label_presets",
    "get_barcode_label_printer_settings",
    "update_barcode_label_printer_settings",
)
SETTINGS_TOOLS = (
    "update_business_info",
    "update_document_numbering_settings",
)
ALL_PLUGIN_TOOLS = FIXED_ASSET_TOOLS + TELEPHONY_TOOLS + BARCODE_TOOLS + SETTINGS_TOOLS
ALWAYS_CONFIRM = (
    "update_fixed_asset_settings",
    "delete_fixed_asset",
    "capitalize_fixed_asset",
    "dispose_fixed_asset",
    "post_fixed_asset_expenditure",
    "post_fixed_asset_depreciation_run",
    "delete_fixed_asset_depreciation_run",
    "update_telephony_settings",
    "delete_telephony_user_extension",
    "create_person_from_telephony_call",
    "create_lead_from_telephony_call",
    "click_to_call",
    "archive_barcode_label_template",
    "update_business_info",
    "update_document_numbering_settings",
)


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
    assert "extra_settings" not in props
    assert "design_json" not in props
    assert "connector_token" not in props


def test_plugin_tools_are_registered_with_strict_schemas():
    parsed = parse_registered_tool_fields()
    for name in ALL_PLUGIN_TOOLS:
        assert name in parsed, name
        fields = parsed[name]
        if fields["is_readonly"]:
            assert fields["requires_approval"] is False
        else:
            assert fields["requires_approval"] is True
            assert fields["is_readonly"] is False

    create = parsed["create_fixed_asset"]
    assert create["required_permissions"] == ["fixed_assets.operate"]
    assert create["risk_level"] == "medium"
    assert CREATE_FIXED_ASSET_SCHEMA["required"] == ["class_id", "name", "acquisition_date", "cost"]
    assert CREATE_FIXED_ASSET_SCHEMA["properties"]["cost"]["exclusiveMinimum"] == 0
    assert CREATE_FIXED_ASSET_SCHEMA["properties"]["method"]["enum"] == ["straight_line", "declining_balance"]
    assert LIST_FIXED_ASSETS_SCHEMA["properties"]["invoice_id"]["type"] == "integer"
    assert GET_FIXED_ASSET_REPORT_SCHEMA["required"] == ["kind"]
    assert GET_FIXED_ASSET_REPORT_SCHEMA["properties"]["kind"]["enum"] == [
        "register",
        "class_summary",
        "depreciation",
        "acquisitions",
        "disposals",
        "idle",
        "locations",
        "expenditures",
    ]
    assert parsed["get_fixed_asset_report"]["is_readonly"] is True
    assert is_write_function("get_fixed_asset_report") is False
    assert CAPITALIZE_FIXED_ASSET_SCHEMA["required"] == ["asset_id", "counterparty_type"]
    assert DISPOSE_FIXED_ASSET_SCHEMA["properties"]["kind"]["enum"] == ["sale", "scrap"]
    for schema in (
        CREATE_FIXED_ASSET_SCHEMA,
        UPDATE_FIXED_ASSET_SETTINGS_SCHEMA,
        CAPITALIZE_FIXED_ASSET_SCHEMA,
        DISPOSE_FIXED_ASSET_SCHEMA,
        GET_FIXED_ASSET_REPORT_SCHEMA,
        UPDATE_TELEPHONY_SETTINGS_SCHEMA,
        CLICK_TO_CALL_SCHEMA,
        UPDATE_BARCODE_PRINTER_SETTINGS_SCHEMA,
        UPDATE_BUSINESS_INFO_SCHEMA,
        UPDATE_DOCUMENT_NUMBERING_SCHEMA,
    ):
        _assert_no_extra_blob(schema)
    assert parsed["capitalize_fixed_asset"]["risk_level"] == "high"
    assert parsed["delete_fixed_asset"]["risk_level"] == "high"
    assert parsed["dispose_fixed_asset"]["required_permissions"] == ["fixed_assets.post"]

    assert parsed["click_to_call"]["required_permissions"] == ["telephony.click_to_call"]
    assert parsed["click_to_call"]["risk_level"] == "high"
    assert parsed["get_telephony_settings"]["is_readonly"] is True
    assert parsed["update_telephony_settings"]["required_permissions"] == ["telephony.manage"]
    assert UPDATE_TELEPHONY_SETTINGS_SCHEMA["properties"]["recording_access_mode"]["enum"] == [
        "permission_based",
        "all_operators",
        "owner_and_managers",
    ]
    assert CLICK_TO_CALL_SCHEMA["required"] == ["destination"]
    assert "create_pbx" not in parsed
    assert "rotate_telephony_token" not in parsed

    printer = UPDATE_BARCODE_PRINTER_SETTINGS_SCHEMA["properties"]["printer_profiles"]
    assert printer["maxItems"] == 50
    assert printer["items"]["properties"]["mode"]["enum"] == ["pdf_spooler", "zpl", "escpos"]
    assert printer["items"]["properties"]["connection"]["enum"] == ["system_default", "tcp", "usb", "ble"]
    assert parsed["archive_barcode_label_template"]["risk_level"] == "high"
    assert parsed["create_barcode_label_from_preset"]["required_permissions"] == ["barcode_labels.design"]

    assert parsed["update_business_info"]["required_permissions"] == ["settings.business"]
    assert parsed["update_business_info"]["risk_level"] == "high"
    assert parsed["update_document_numbering_settings"]["required_permissions"] == ["settings.join"]
    assert "invoice_profit_calculation_method" not in UPDATE_BUSINESS_INFO_SCHEMA["properties"]
    assert "default_credit_limit" not in UPDATE_BUSINESS_INFO_SCHEMA["properties"]
    reset = UPDATE_DOCUMENT_NUMBERING_SCHEMA["properties"]["reset_period"]
    assert any(branch.get("type") == "null" for branch in reset["anyOf"])


def test_manifest_marks_plugin_writes_and_high_risk_confirm():
    for name in ALL_PLUGIN_TOOLS:
        entry = get_manifest_entry(name)
        assert entry is not None, name
    for name in ALWAYS_CONFIRM:
        entry = get_manifest_entry(name)
        assert entry is not None and entry.always_confirm is True and entry.intent_write is True, name
    assert get_manifest_entry("delete_fixed_asset").side_effect == "delete"
    assert get_manifest_entry("delete_fixed_asset_depreciation_run").side_effect == "delete"
    assert get_manifest_entry("delete_telephony_user_extension").side_effect == "delete"
    assert get_manifest_entry("create_fixed_asset").intent_write is True
    assert get_manifest_entry("create_fixed_asset").always_confirm is False
    assert get_manifest_entry("get_fixed_asset_settings").intent_write is False
    biz = get_manifest_entry("get_business_info")
    assert "update_business_info" in (biz.companion_tools if biz else ())
    numbering = get_manifest_entry("get_document_numbering_settings")
    assert "update_document_numbering_settings" in (numbering.companion_tools if numbering else ())
    plugins = get_manifest_entry("list_business_plugins")
    assert "get_telephony_settings" in (plugins.companion_tools if plugins else ())
    assert is_write_function("create_fixed_asset") is True
    assert is_write_function("click_to_call") is True
    assert is_write_function("update_business_info") is True
    assert is_write_function("get_telephony_settings") is False
    assert is_write_function("list_barcode_label_presets") is False


def test_fixed_asset_settings_omit_extra_blob_and_pin_tenant():
    with patch(
        "app.services.fixed_asset_service.get_settings",
        return_value={"enabled": True, "extra_settings": {"secret": 1}, "extra_info": {"x": 1}},
    ) as get_settings:
        out = get_fixed_asset_settings_handler({}, _ctx())
    assert out["enabled"] is True
    assert "extra_settings" not in out
    assert "extra_info" not in out
    assert get_settings.call_args.args[1] == 7

    with patch(
        "app.services.fixed_asset_service.update_settings",
        return_value={"plaque_prefix": "FA", "extra_settings": {"keep": False}},
    ) as update:
        out = update_fixed_asset_settings_handler({"plaque_prefix": "FA"}, _ctx())
    assert out["plaque_prefix"] == "FA"
    assert "extra_settings" not in out
    assert update.call_args.args[1] == 7
    assert update.call_args.args[2] == {"plaque_prefix": "FA"}


def test_fixed_asset_writes_pin_tenant_and_convert_api_error():
    with patch(
        "app.services.fixed_asset_service.create_asset",
        return_value={"id": 4, "status": "draft"},
    ) as create:
        result = create_fixed_asset_handler(
            {
                "class_id": 1,
                "name": "لیفتراک",
                "acquisition_date": "2026-01-01",
                "cost": 1000,
                "business_id": 99,
            },
            _ctx(),
        )
    assert result["id"] == 4
    assert create.call_args.args[1] == 7

    with patch(
        "app.services.fixed_asset_service.capitalize_asset",
        return_value={"id": 4, "status": "capitalized"},
    ) as cap:
        capitalize_fixed_asset_handler(
            {"asset_id": 4, "counterparty_type": "bank", "bank_account_id": 2},
            _ctx(),
        )
    assert cap.call_args.args[1] == 7
    assert cap.call_args.args[2] == 4
    assert cap.call_args.args[3]["counterparty_type"] == "bank"

    with patch(
        "app.services.fixed_asset_service.delete_asset",
        side_effect=ApiError("ASSET_NOT_DRAFT", "فقط دارایی پیش‌نویسِ سرمایه‌نشده قابل حذف است.", http_status=409),
    ):
        with pytest.raises(ValueError, match="پیش‌نویس"):
            delete_fixed_asset_handler({"asset_id": 4}, _ctx())

    with patch(
        "app.services.fixed_asset_service.list_assets",
        return_value={"total": 0, "items": []},
    ) as listed:
        list_fixed_assets_handler({"invoice_id": 88, "status": "capitalized"}, _ctx())
    kwargs = listed.call_args.kwargs
    assert listed.call_args.args[1] == 7
    assert kwargs["invoice_id"] == 88
    assert kwargs["status"] == "capitalized"

    with patch(
        "app.services.fixed_asset_service.create_asset",
        return_value={"id": 5, "method": "declining_balance"},
    ) as create_declining:
        create_fixed_asset_handler(
            {
                "class_id": 1,
                "name": "خودرو",
                "acquisition_date": "2026-01-01",
                "cost": 2000,
                "method": "declining",
            },
            _ctx(),
        )
    assert create_declining.call_args.args[2]["method"] == "declining_balance"


def test_telephony_inactive_plugin_and_token_redaction():
    with patch(
        "app.core.telephony_plugin_dependency.check_telephony_plugin_active",
        return_value=False,
    ):
        with pytest.raises(ValueError, match="افزونه تلفن"):
            get_telephony_settings_handler({}, _ctx())
        with pytest.raises(ValueError, match="افزونه تلفن"):
            click_to_call_handler({"destination": "09120000000"}, _ctx())

    with patch(
        "app.core.telephony_plugin_dependency.check_telephony_plugin_active",
        return_value=True,
    ), patch(
        "app.services.telephony.telephony_service.get_or_create_settings",
        return_value=object(),
    ), patch(
        "app.services.telephony.telephony_service.settings_to_dict",
        return_value={
            "screen_pop_enabled": True,
            "extra_settings": {"token": "x"},
            "ui_preferences": {"theme": "dark"},
            "number_normalization_rules": {"strip": True},
        },
    ):
        out = get_telephony_settings_handler({}, _ctx())
    assert out["screen_pop_enabled"] is True
    assert "extra_settings" not in out
    assert "ui_preferences" not in out
    assert "number_normalization_rules" not in out

    fake_scope = MagicMock(can_manage=False, view_all=False)
    with patch(
        "app.core.telephony_plugin_dependency.check_telephony_plugin_active",
        return_value=True,
    ), patch(
        "app.services.telephony.telephony_access.resolve_scope",
        return_value=fake_scope,
    ), patch(
        "app.services.telephony.telephony_service.list_pbx",
        return_value=[{
            "id": 1,
            "name": "سانترال",
            "connector_token": "hsx_tel_secret",
            "install_hint": "copy once",
            "settings": {"softphone": {"relay_enabled": True}},
        }],
    ):
        listed = list_telephony_pbx_handler({}, _ctx())
    item = listed["items"][0]
    assert item["id"] == 1
    assert "connector_token" not in item
    assert "install_hint" not in item
    assert "settings" not in item

    with patch(
        "app.core.telephony_plugin_dependency.check_telephony_plugin_active",
        return_value=True,
    ), patch(
        "app.services.telephony.telephony_service.dashboard_summary",
        return_value={"pbx_connections": [{"id": 1, "connector_token": "leak", "settings": {}}]},
    ):
        dash = get_telephony_dashboard_handler({}, _ctx())
    assert "connector_token" not in dash["pbx_connections"][0]
    assert "settings" not in dash["pbx_connections"][0]


def test_telephony_writes_pin_tenant():
    with patch(
        "app.core.telephony_plugin_dependency.check_telephony_plugin_active",
        return_value=True,
    ), patch(
        "app.services.telephony.telephony_service.update_settings",
        return_value={"screen_pop_enabled": False, "extra_settings": {}},
    ) as update:
        out = update_telephony_settings_handler({"screen_pop_enabled": False}, _ctx())
    assert "extra_settings" not in out
    assert update.call_args.args[1] == 7

    with patch(
        "app.core.telephony_plugin_dependency.check_telephony_plugin_active",
        return_value=True,
    ), patch(
        "app.services.telephony.telephony_service.click_to_call",
        return_value={"status": "originated"},
    ) as call:
        click_to_call_handler({"destination": "02191000000", "extension_id": 3}, _ctx())
    assert call.call_args.args[1] == 7
    assert call.call_args.args[2] == 9
    assert call.call_args.args[3]["destination"] == "02191000000"


def test_barcode_inactive_plugin_and_preset_create():
    with patch(
        "app.core.barcode_label_plugin_dependency.check_barcode_label_plugin_active",
        return_value=False,
    ):
        with pytest.raises(ValueError, match="برچسب بارکد"):
            list_barcode_label_templates_handler({}, _ctx())

    with patch(
        "app.core.barcode_label_plugin_dependency.check_barcode_label_plugin_active",
        return_value=True,
    ), patch(
        "app.services.barcode_label_service.create_from_preset",
        return_value={"id": 11, "status": "draft"},
    ) as create:
        out = create_barcode_label_from_preset_handler(
            {"preset_code": "product_40x30", "name": "لیبل کالا"},
            _ctx(),
        )
    assert out["id"] == 11
    assert create.call_args.kwargs["preset_code"] == "product_40x30"
    assert create.call_args.kwargs["user_id"] == 9
    assert create.call_args.args[1] == 7

    with patch(
        "app.core.barcode_label_plugin_dependency.check_barcode_label_plugin_active",
        return_value=True,
    ), patch(
        "app.services.barcode_label_service.upsert_printer_settings",
        return_value={"active_profile_id": "shop"},
    ) as upsert:
        update_barcode_label_printer_settings_handler(
            {"printer_profiles": [{"id": "shop", "name": "فروشگاه", "mode": "zpl"}]},
            _ctx(),
        )
    assert upsert.call_args.args[1] == 7


def test_update_business_info_owner_only_and_identity_fields():
    with patch(
        "app.services.business_service.update_business",
        return_value=None,
    ):
        with pytest.raises(ValueError, match="فقط برای مالک"):
            update_business_info_handler({"name": "شرکت نو"}, _ctx())

    with patch(
        "app.services.business_service.update_business",
        return_value={"id": 7, "name": "شرکت نو"},
    ) as update:
        out = update_business_info_handler(
            {"name": "شرکت نو", "business_type": "شرکت", "business_id": 99},
            _ctx(),
        )
    assert out["name"] == "شرکت نو"
    assert update.call_args.args[1] == 7
    assert update.call_args.args[3] == 9
    payload = update.call_args.args[2]
    assert payload.name == "شرکت نو"
    assert not hasattr(payload, "invoice_profit_calculation_method") or payload.invoice_profit_calculation_method is None


def test_document_numbering_pins_tenant_on_create_and_update():
    db = MagicMock()
    db.query.return_value.filter.return_value.first.return_value = None
    added = []
    db.add.side_effect = lambda row: added.append(row)
    fake = MagicMock()
    fake.dict.return_value = {
        "document_type": "invoice_sales",
        "business_id": 7,
        "prefix": "INV",
    }
    with patch(
        "adapters.api.v1.schemas.DocumentNumberingSettingResponse.from_orm",
        return_value=fake,
    ):
        result = update_document_numbering_settings_handler(
            {"document_type": "invoice_sales", "prefix": "INV", "business_id": 99},
            _ctx(db=db),
        )
    assert added[0].business_id == 7
    assert added[0].document_type == "invoice_sales"
    assert result["business_id"] == 7

    existing = MagicMock()
    existing.business_id = 7
    existing.document_type = "invoice_sales"
    db.query.return_value.filter.return_value.first.return_value = existing
    with patch(
        "adapters.api.v1.schemas.DocumentNumberingSettingResponse.from_orm",
        return_value=fake,
    ):
        update_document_numbering_settings_handler(
            {"document_type": "invoice_sales", "prefix": "SALE"},
            _ctx(db=db),
        )
    assert existing.prefix == "SALE"
    assert existing.business_id == 7
