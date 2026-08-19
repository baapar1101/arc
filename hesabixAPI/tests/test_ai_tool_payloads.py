"""نگاشت payload فاکتور AI و قرارداد فیلتر/اسکیما."""
from __future__ import annotations

from datetime import date

from app.services.ai.ai_query_filter_catalog import resolve_filter_property
from app.services.ai.ai_query_filter_service import normalize_filter_items
from app.services.ai.ai_tool_payloads import (
    CREATE_INVOICE_PARAMETERS_SCHEMA,
    build_create_check_payload,
    build_create_invoice_payload,
    build_create_receipt_payment_payload,
    build_create_transfer_payload,
    build_create_warehouse_document_payload,
    build_create_workflow_payload,
    build_update_invoice_payload,
    normalize_ai_invoice_line,
    normalize_workflow_graph,
)
from app.services.ai.ai_tool_query_params import ai_list_parameters_schema


def test_normalize_line_moves_unit_price_to_extra_info():
    line = normalize_ai_invoice_line(
        {"product_id": "12", "quantity": 2, "unit_price": 150000}
    )
    assert line["product_id"] == 12
    assert line["quantity"] == 2.0
    assert line["extra_info"]["unit_price"] == 150000


def test_build_create_invoice_payload_session_896_shape():
    payload = build_create_invoice_payload(
        {
            "invoice_type": "invoice_sales",
            "document_date": "2026-08-18",
            "currency_id": 1,
            "person_id": 176105,
            "lines": [
                {
                    "product_id": 44,
                    "quantity": 1,
                    "unit_price": 25000000,
                }
            ],
        }
    )
    assert payload["person_id"] == 176105
    assert payload["extra_info"]["person_id"] == 176105
    assert payload["lines"][0]["extra_info"]["unit_price"] == 25000000
    assert payload["invoice_type"] == "invoice_sales"
    assert payload["currency_id"] == 1


def test_build_create_invoice_aliases_and_defaults():
    payload = build_create_invoice_payload(
        {
            "invoice_type": "فروش",
            "customer_id": 9,
            "lines": [{"product_id": 1, "quantity": 1, "unit_price": 10}],
        }
    )
    assert payload["invoice_type"] == "invoice_sales"
    assert payload["person_id"] == 9
    assert payload["document_date"] == date.today().isoformat()


def test_create_invoice_schema_requires_person_and_describes_unit_price():
    schema = CREATE_INVOICE_PARAMETERS_SCHEMA
    assert "person_id" in schema["required"]
    assert "invoice_type" in schema["required"]
    assert "lines" in schema["required"]
    line_props = schema["properties"]["lines"]["items"]["properties"]
    assert "unit_price" in line_props
    assert "description" in line_props["unit_price"]
    assert len(schema["properties"]["person_id"]["description"]) > 20


def test_filter_aliases_sale_date_and_person_type():
    assert resolve_filter_property("invoice", "sale_date") == "document_date"
    assert resolve_filter_property("person", "name") == "alias_name"
    items = normalize_filter_items(
        [{"property": "sale_date", "operator": ">,", "value": "2026-01-01"}],
        entity="invoice",
    )
    assert items[0]["property"] == "document_date"
    assert items[0]["operator"] == ">"


def test_filter_id_on_person_is_rejected_with_search_hint():
    try:
        resolve_filter_property("person", "id")
        assert False, "expected ValueError"
    except ValueError as exc:
        assert "search" in str(exc)


def test_search_schema_lists_allowed_filter_properties():
    schema = ai_list_parameters_schema(entity="invoice")
    desc = schema["properties"]["filters"]["description"]
    assert "document_date" in desc
    assert schema["properties"]["take"]["maximum"] == 100


def test_receipt_payment_maps_bank_id_not_chart_account():
    payload = build_create_receipt_payment_payload(
        {
            "type": "دریافت",
            "person_id": 10,
            "amount": 5000,
            "account_type": "بانک",
            "account_id": 3,
            "currency_id": 1,
        }
    )
    assert payload["document_type"] == "receipt"
    assert payload["person_lines"][0]["person_id"] == 10
    line = payload["account_lines"][0]
    assert line["transaction_type"] == "bank"
    assert line["bank_id"] == 3
    assert "account_id" not in line


def test_create_check_aliases_and_requires_person_for_received():
    payload = build_create_check_payload(
        {
            "type": "دریافتی",
            "check_number": "123",
            "amount": 100,
            "issue_date": "2026-08-01",
            "due_date": "2026-09-01",
            "person_id": 7,
            "currency_id": 1,
        }
    )
    assert payload["type"] == "received"
    assert payload["currency_id"] == 1
    try:
        build_create_check_payload(
            {
                "type": "received",
                "check_number": "1",
                "amount": 1,
                "issue_date": "2026-08-01",
                "due_date": "2026-09-01",
                "currency_id": 1,
            }
        )
        assert False, "expected ValueError"
    except ValueError as exc:
        assert "person_id" in str(exc)


def test_create_transfer_and_warehouse_and_workflow_payloads():
    tr = build_create_transfer_payload(
        {
            "from_account_type": "صندوق",
            "from_account_id": 2,
            "to_account_type": "bank",
            "to_account_id": 4,
            "amount": 80,
            "currency_id": 1,
        }
    )
    assert tr["source"] == {"type": "cash_register", "id": 2}
    assert tr["destination"]["type"] == "bank"
    assert tr["document_date"] == date.today().isoformat()

    wh = build_create_warehouse_document_payload(
        {
            "doc_type": "ورود",
            "warehouse_id": 9,
            "lines": [{"product_id": 1, "quantity": 2}],
        }
    )
    assert wh["doc_type"] == "receipt"
    assert wh["warehouse_id_to"] == 9
    assert wh["lines"][0]["product_id"] == 1

    wf = build_create_workflow_payload(
        {
            "name": "تست",
            "status": "draft",
            "workflow_data": {"nodes": [{"id": "a", "type": "trigger"}]},
        }
    )
    assert wf["status"] == "پیش‌نویس"
    assert wf["workflow_data"]["connections"] == []
    graph = normalize_workflow_graph({"nodes": []})
    assert graph["connections"] == []


def test_update_invoice_normalizes_lines_when_sent():
    payload = build_update_invoice_payload(
        {
            "invoice_id": 5,
            "person_id": 8,
            "lines": [{"product_id": 1, "quantity": 1, "unit_price": 20}],
        }
    )
    assert payload["person_id"] == 8
    assert payload["extra_info"]["person_id"] == 8
    assert payload["lines"][0]["extra_info"]["unit_price"] == 20
