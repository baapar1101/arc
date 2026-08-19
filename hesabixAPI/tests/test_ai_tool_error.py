"""تست نرمال‌سازی خطای ابزار برای مدل."""
from __future__ import annotations

from app.services.ai.ai_tool_error import normalize_tool_error, unknown_tool_result


def test_unknown_tool_is_not_approval():
    payload = unknown_tool_result("invented_tool")
    assert payload["error"] == "UNKNOWN_TOOL"
    assert payload["ok"] is False
    assert payload["retryable"] is True
    assert payload["error"] != "APPROVAL_REQUIRED"
    assert "invented_tool" in payload["message"]


def test_unexpected_db_keyword_becomes_invalid_arguments():
    exc = TypeError(
        "create_session_plan_handler() got an unexpected keyword argument 'db'"
    )
    payload = normalize_tool_error(
        "create_session_plan",
        exc,
        schema={"properties": {"items": {}, "plan_title": {}}},
    )
    assert payload["error"] == "INVALID_ARGUMENTS"
    assert payload["retryable"] is True
    assert "db" in (payload.get("hint_fa") or "")
    assert "items" in payload["expected_args"]
    assert payload.get("hint_fa")


def test_not_found_maps_to_unknown_tool():
    payload = normalize_tool_error(
        "foo_bar",
        ValueError("Function 'foo_bar' not found in registry"),
    )
    assert payload["error"] == "UNKNOWN_TOOL"


def test_api_error_keeps_business_code():
    from app.core.responses import ApiError

    payload = normalize_tool_error(
        "create_invoice",
        ApiError("PERSON_REQUIRED", "person_id is required for this invoice type", http_status=400),
    )
    assert payload["error"] == "PERSON_REQUIRED"
    assert "person_id" in payload["message"]
    assert payload.get("detail")
    assert "search_persons" in (payload.get("hint_fa") or "")


def test_create_invoice_schema_nested_expected_args():
    from app.services.ai.ai_tool_payloads import CREATE_INVOICE_PARAMETERS_SCHEMA

    payload = normalize_tool_error(
        "create_invoice",
        ValueError("lines الزامی است و باید حداقل یک قلم کالا داشته باشد."),
        schema=CREATE_INVOICE_PARAMETERS_SCHEMA,
    )
    assert "lines[].unit_price" in payload["expected_args"]
    assert "person_id" in payload["required_args"]
