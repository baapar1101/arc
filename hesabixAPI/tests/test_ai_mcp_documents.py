"""Tenant-bound MCP tools for the accounting-documents page write cycle."""
from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest

from app.core.responses import ApiError
from app.services.ai.ai_function_extensions_mcp_documents import (
    BULK_DELETE_MANUAL_DOCUMENTS_SCHEMA,
    CREATE_MANUAL_DOCUMENT_SCHEMA,
    DELETE_MANUAL_DOCUMENT_SCHEMA,
    TYPES_SUMMARY_SCHEMA,
    bulk_delete_manual_documents_handler,
    create_manual_document_handler,
    delete_manual_document_handler,
    get_document_types_summary_handler,
    update_manual_document_handler,
)
from app.services.ai.ai_tool_catalog_quality import parse_registered_tool_fields
from app.services.ai.ai_tool_manifest import get_manifest_entry
from app.services.ai.ai_write_guard import is_write_function


def _ctx(*, business_id: int = 7, user_id: int = 9, db=None):
    user = MagicMock()
    user.get_user_id.return_value = user_id
    return {
        "db": db if db is not None else MagicMock(),
        "business_id": business_id,
        "user_context": user,
    }


def _query_db(*, fy=None, document=None, documents=None):
    from adapters.db.models.document import Document
    from adapters.db.models.fiscal_year import FiscalYear

    db = MagicMock()

    def query(model):
        q = MagicMock()
        q.filter.return_value = q
        if model is FiscalYear:
            q.first.return_value = fy
        elif model is Document:
            q.first.return_value = document
            q.all.return_value = list(documents or ([] if document is None else [document]))
        else:
            q.first.return_value = None
            q.all.return_value = []
        return q

    db.query.side_effect = query
    return db


def test_document_tools_are_registered_with_strict_schemas():
    parsed = parse_registered_tool_fields()
    for name in (
        "get_document_types_summary",
        "create_manual_document",
        "update_manual_document",
        "delete_manual_document",
        "bulk_delete_manual_documents",
    ):
        assert name in parsed, name
    create = parsed["create_manual_document"]
    assert create["requires_approval"] is True
    assert create["is_readonly"] is False
    assert create["risk_level"] == "high"
    assert create["required_permissions"] == ["accounting_documents.write"]
    assert CREATE_MANUAL_DOCUMENT_SCHEMA["additionalProperties"] is False
    assert "extra_info" not in CREATE_MANUAL_DOCUMENT_SCHEMA["properties"]
    assert "fiscal_year_id" not in CREATE_MANUAL_DOCUMENT_SCHEMA["properties"]
    lines = CREATE_MANUAL_DOCUMENT_SCHEMA["properties"]["lines"]
    assert lines["minItems"] == 2
    assert lines["maxItems"] == 200
    assert lines["items"]["additionalProperties"] is False
    assert "extra_info" not in lines["items"]["properties"]

    delete = parsed["delete_manual_document"]
    assert delete["required_permissions"] == ["accounting_documents.delete"]
    assert delete["risk_level"] == "high"
    assert delete["requires_approval"] is True
    assert BULK_DELETE_MANUAL_DOCUMENTS_SCHEMA["properties"]["document_ids"]["maxItems"] == 100
    assert DELETE_MANUAL_DOCUMENT_SCHEMA["additionalProperties"] is False
    summary = parsed["get_document_types_summary"]
    assert summary["is_readonly"] is True
    assert summary["required_permissions"] == ["accounting_documents.view"]
    assert TYPES_SUMMARY_SCHEMA["additionalProperties"] is False


def test_manifest_marks_document_writes_and_delete_confirm():
    create = get_manifest_entry("create_manual_document")
    update = get_manifest_entry("update_manual_document")
    delete = get_manifest_entry("delete_manual_document")
    bulk = get_manifest_entry("bulk_delete_manual_documents")
    summary = get_manifest_entry("get_document_types_summary")
    assert create is not None and create.intent_write is True and create.always_confirm is False
    assert update is not None and update.intent_write is True
    assert delete is not None and delete.always_confirm is True and delete.side_effect == "delete"
    assert bulk is not None and bulk.always_confirm is True and bulk.intent_write is True
    assert summary is not None and summary.intent_write is False
    assert is_write_function("create_manual_document") is True
    assert is_write_function("delete_manual_document") is True
    assert is_write_function("get_document_types_summary") is False


def test_create_manual_document_uses_current_fy_and_policy():
    fy = SimpleNamespace(id=11)
    db = _query_db(fy=fy)
    context = _ctx(db=db)
    args = {
        "document_date": "2026-10-29",
        "currency_id": 1,
        "lines": [
            {"account_id": 10, "debit": 100, "credit": 0},
            {"account_id": 20, "debit": 0, "credit": 100},
        ],
    }
    with (
        patch(
            "app.services.document_monetization_service.ensure_document_policy_allows_creation",
            return_value={"allowed": True},
        ) as policy,
        patch(
            "app.services.document_service.create_manual_document",
            return_value={"id": 44, "document_type": "manual"},
        ) as create,
    ):
        result = create_manual_document_handler(args, context)
    assert result["id"] == 44
    policy.assert_called_once()
    assert policy.call_args.kwargs["document_type"] == "manual"
    assert policy.call_args.kwargs["amount"] == 100
    create.assert_called_once()
    _, bid, fy_id, user_id, data = create.call_args.args
    assert bid == 7
    assert fy_id == 11
    assert user_id == 9
    assert "extra_info" not in data
    assert data["currency_id"] == 1


def test_create_manual_document_requires_current_fiscal_year():
    db = _query_db(fy=None)
    with pytest.raises(ValueError, match="سال مالی جاری"):
        create_manual_document_handler(
            {
                "document_date": "2026-10-29",
                "currency_id": 1,
                "lines": [
                    {"account_id": 1, "debit": 1, "credit": 0},
                    {"account_id": 2, "debit": 0, "credit": 1},
                ],
            },
            _ctx(db=db),
        )


def test_update_rejects_other_tenant_and_non_manual():
    db = _query_db(document=None)
    with pytest.raises(ValueError, match="کسب‌وکار متصل"):
        update_manual_document_handler({"document_id": 5, "description": "x"}, _ctx(db=db))

    other = SimpleNamespace(id=5, business_id=7, document_type="invoice_sales", fiscal_year_id=11)
    db = _query_db(fy=SimpleNamespace(id=11), document=other)
    with pytest.raises(ValueError, match="فقط اسناد دستی"):
        update_manual_document_handler({"document_id": 5}, _ctx(db=db))


def test_update_rejects_closed_fiscal_year():
    doc = SimpleNamespace(id=5, business_id=7, document_type="manual", fiscal_year_id=3)
    db = _query_db(fy=SimpleNamespace(id=11), document=doc)
    with pytest.raises(ValueError, match="سال مالی جاری"):
        update_manual_document_handler({"document_id": 5, "description": "x"}, _ctx(db=db))


def test_update_calls_service_for_tenant_manual_current_fy():
    doc = SimpleNamespace(id=5, business_id=7, document_type="manual", fiscal_year_id=11)
    db = _query_db(fy=SimpleNamespace(id=11), document=doc)
    with patch(
        "app.services.document_service.update_manual_document",
        return_value={"id": 5},
    ) as update:
        result = update_manual_document_handler(
            {"document_id": 5, "description": "اصلاح"},
            _ctx(db=db),
        )
    assert result["id"] == 5
    update.assert_called_once()
    assert update.call_args.args[1] == 5
    assert update.call_args.args[2] == {"description": "اصلاح"}


def test_delete_pins_tenant_and_requires_manual():
    db = _query_db(document=None)
    with patch(
        "app.core.permissions.has_business_permission_for_business",
        return_value=True,
    ):
        with pytest.raises(ValueError, match="کسب‌وکار متصل"):
            delete_manual_document_handler({"document_id": 8}, _ctx(db=db))

    auto = SimpleNamespace(id=8, business_id=7, document_type="expense")
    db = _query_db(document=auto)
    with patch(
        "app.core.permissions.has_business_permission_for_business",
        return_value=True,
    ), patch("app.services.document_service.delete_document") as delete:
        with pytest.raises(ValueError, match="فقط اسناد دستی"):
            delete_manual_document_handler({"document_id": 8}, _ctx(db=db))
        delete.assert_not_called()


def test_delete_manual_document_success():
    doc = SimpleNamespace(id=8, business_id=7, document_type="manual")
    db = _query_db(document=doc)
    with patch(
        "app.core.permissions.has_business_permission_for_business",
        return_value=True,
    ), patch("app.services.document_service.delete_document", return_value=True) as delete:
        result = delete_manual_document_handler({"document_id": 8}, _ctx(db=db))
    assert result == {"deleted": True, "document_id": 8}
    delete.assert_called_once()


def test_delete_rejects_missing_permission():
    doc = SimpleNamespace(id=8, business_id=7, document_type="manual")
    db = _query_db(document=doc)
    with patch(
        "app.core.permissions.has_business_permission_for_business",
        return_value=False,
    ):
        with pytest.raises(ValueError, match="accounting_documents.delete"):
            delete_manual_document_handler({"document_id": 8}, _ctx(db=db))


def test_bulk_delete_rejects_foreign_or_missing_ids():
    local = SimpleNamespace(id=1, business_id=7, document_type="manual", code="A")
    db = _query_db(documents=[local])
    with patch(
        "app.core.permissions.has_business_permission_for_business",
        return_value=True,
    ):
        with pytest.raises(ValueError, match="متعلق به کسب‌وکار"):
            bulk_delete_manual_documents_handler(
                {"document_ids": [1, 99]},
                _ctx(db=db),
            )


def test_bulk_delete_skips_auto_and_deletes_manual():
    manual = SimpleNamespace(id=1, business_id=7, document_type="manual", code="M1")
    auto = SimpleNamespace(id=2, business_id=7, document_type="receipt", code="R1")
    db = _query_db(documents=[manual, auto])
    with patch(
        "app.core.permissions.has_business_permission_for_business",
        return_value=True,
    ), patch("app.services.document_service.delete_document", return_value=True) as delete:
        result = bulk_delete_manual_documents_handler(
            {"document_ids": [1, 2]},
            _ctx(db=db),
        )
    delete.assert_called_once()
    assert delete.call_args.args[1] == 1
    assert result["deleted_count"] == 1
    assert result["deleted_ids"] == [1]
    assert result["skipped_auto_documents"][0]["id"] == 2


def test_bulk_delete_rejects_duplicate_ids():
    with pytest.raises(ValueError, match="تکراری"):
        bulk_delete_manual_documents_handler(
            {"document_ids": [1, 1]},
            _ctx(),
        )


def test_bulk_delete_converts_api_error_per_item():
    doc = SimpleNamespace(id=3, business_id=7, document_type="manual", code="M")
    db = _query_db(documents=[doc])
    with patch(
        "app.core.permissions.has_business_permission_for_business",
        return_value=True,
    ), patch(
        "app.services.document_service.delete_document",
        side_effect=ApiError("DOCUMENT_HAS_WALLET_TRANSACTIONS", "دارای تراکنش کیف پول", http_status=409),
    ):
        result = bulk_delete_manual_documents_handler({"document_ids": [3]}, _ctx(db=db))
    assert result["deleted_count"] == 0
    assert result["errors"][0]["id"] == 3
    assert "کیف پول" in result["errors"][0]["error"]


def test_types_summary_uses_session_business_id():
    db = MagicMock()
    with patch(
        "app.services.document_service.get_document_types_summary",
        return_value={"manual": 4, "invoice_sales": 2},
    ) as summary:
        result = get_document_types_summary_handler({"business_id": 99}, _ctx(business_id=7, db=db))
    summary.assert_called_once_with(db, 7)
    assert result == {"summary": {"manual": 4, "invoice_sales": 2}, "total": 6}
