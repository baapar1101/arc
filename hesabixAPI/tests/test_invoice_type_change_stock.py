from decimal import Decimal
from unittest.mock import MagicMock

from app.services.invoice_service import (
    INVOICE_PRODUCTION,
    INVOICE_PURCHASE,
    INVOICE_SALES,
    _INVENTORY_LEDGER_REFRESH_TYPES,
    _resolve_invoice_type_from_payload,
    _sanitize_extra_info_for_invoice_type_change,
    _stamp_movement_on_invoice_lines,
    _warehouse_doc_cancels_invoice_sourced_wh,
    _warehouse_document_is_invoice_sourced,
)


def test_inventory_ledger_refresh_types_include_purchase() -> None:
    assert INVOICE_PURCHASE in _INVENTORY_LEDGER_REFRESH_TYPES
    assert INVOICE_SALES not in _INVENTORY_LEDGER_REFRESH_TYPES


def test_resolve_invoice_type_from_payload_prefers_request() -> None:
    data = {"invoice_type": INVOICE_PURCHASE}
    assert _resolve_invoice_type_from_payload(data, fallback=INVOICE_SALES) == INVOICE_PURCHASE


def test_resolve_invoice_type_from_payload_falls_back() -> None:
    data: dict = {}
    assert _resolve_invoice_type_from_payload(data, fallback=INVOICE_SALES) == INVOICE_SALES


def test_stamp_movement_on_invoice_lines_purchase() -> None:
    lines = [{"product_id": 1, "quantity": 5, "extra_info": {"movement": "out"}}]
    _stamp_movement_on_invoice_lines(INVOICE_PURCHASE, lines)
    assert lines[0]["extra_info"]["movement"] == "in"


def test_stamp_movement_on_invoice_lines_sales() -> None:
    lines = [{"product_id": 1, "quantity": 5, "extra_info": {"movement": "in"}}]
    _stamp_movement_on_invoice_lines(INVOICE_SALES, lines)
    assert lines[0]["extra_info"]["movement"] == "out"


def test_stamp_movement_skips_production() -> None:
    lines = [{"product_id": 1, "quantity": 5, "extra_info": {"movement": "in"}}]
    _stamp_movement_on_invoice_lines(INVOICE_PRODUCTION, lines)
    assert lines[0]["extra_info"]["movement"] == "in"


def test_sanitize_extra_info_removes_sales_fields_on_purchase() -> None:
    extra = {
        "person_id": 9,
        "installment_plan": {"schedule": []},
        "seller_id": 3,
        "commission": {"type": "percent", "value": 5},
        "purchase_accounting_mode": "direct",
    }
    cleaned = _sanitize_extra_info_for_invoice_type_change(extra, INVOICE_PURCHASE, INVOICE_SALES)
    assert cleaned["person_id"] == 9
    assert "installment_plan" not in cleaned
    assert "seller_id" not in cleaned
    assert "commission" not in cleaned
    assert cleaned.get("purchase_accounting_mode") == "direct"


def test_warehouse_document_is_invoice_sourced_by_source_type() -> None:
    wh = MagicMock()
    wh.source_type = "invoice"
    wh.source_document_id = None
    assert _warehouse_document_is_invoice_sourced(MagicMock(), 1, wh) is True


def test_warehouse_doc_cancels_invoice_sourced_wh() -> None:
    db = MagicMock()
    cancel_wh = MagicMock()
    cancel_wh.extra_info = {"cancels_warehouse_document_id": 42}

    src_wh = MagicMock()
    src_wh.source_type = "invoice"
    src_wh.source_document_id = 100

    db.query.return_value.filter.return_value.first.return_value = src_wh
    assert _warehouse_doc_cancels_invoice_sourced_wh(db, 1, cancel_wh) is True
