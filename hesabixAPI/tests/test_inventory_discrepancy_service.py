from datetime import date
from types import SimpleNamespace

import pytest

from app.core.responses import ApiError
from app.services.inventory_discrepancy_service import (
    _correction_lines_by_case_line,
    _correction_request_fingerprint,
    _serialize,
    create_goods_income_correction,
)


def test_serialize_includes_labels_needed_by_discrepancy_ui():
    invoice = SimpleNamespace(code="QS-42", document_date=SimpleNamespace(isoformat=lambda: "2026-10-12"))
    product = SimpleNamespace(name="کالای نمونه", code="P-1", base_purchase_price=125_000)
    warehouse = SimpleNamespace(name="انبار اصلی")
    line = SimpleNamespace(
        id=7,
        product_id=11,
        product=product,
        warehouse_id=3,
        warehouse=warehouse,
        invoice_item_line_id=13,
        available_quantity=0,
        requested_quantity=2,
        shortage_quantity=2,
        resolved_quantity=0,
        resolution_unit_cost=None,
    )
    case = SimpleNamespace(
        id=5,
        business_id=1,
        invoice_document_id=42,
        invoice_document=invoice,
        warehouse_document_id=9,
        resolution_document_id=None,
        status="open",
        source_type="quick_sale",
        reason_code="urgent_sale",
        reason_note=None,
        created_by_user_id=2,
        resolved_by_user_id=None,
        resolution_type=None,
        created_at=None,
        resolved_at=None,
        lines=[line],
    )

    result = _serialize(case)

    assert result["invoice_code"] == "QS-42"
    assert result["invoice_date"] == "2026-10-12"
    assert result["lines"][0]["product_name"] == "کالای نمونه"
    assert result["lines"][0]["product_code"] == "P-1"
    assert result["lines"][0]["warehouse_name"] == "انبار اصلی"
    assert result["lines"][0]["suggested_unit_cost"] == 125_000


def test_correction_lines_are_matched_by_case_line_not_only_product():
    lines = [
        {
            "product_id": 11,
            "warehouse_id": 1,
            "unit_cost": 100,
            "extra_info": {"inventory_discrepancy_line_id": 7},
        },
        {
            "product_id": 11,
            "warehouse_id": 2,
            "unit_cost": 120,
            "extra_info": {"inventory_discrepancy_line_id": 8},
        },
    ]

    indexed = _correction_lines_by_case_line(lines)

    assert indexed[7]["warehouse_id"] == 1
    assert indexed[8]["warehouse_id"] == 2


def test_stock_correction_reuses_document_for_same_request_token(monkeypatch):
    from app.services import goods_expense_income_service
    from app.services import inventory_discrepancy_service as service

    document_date = date(2026, 10, 17)
    lines = [{"product_id": 11, "warehouse_id": 3, "quantity": 2}]
    existing = SimpleNamespace(
        id=91,
        extra_info={
            "request_fingerprint": _correction_request_fingerprint(
                document_date,
                lines,
            )
        },
    )
    monkeypatch.setattr(service, "acquire_transaction_lock", lambda *_args: None)
    monkeypatch.setattr(
        service,
        "_find_quick_sales_correction_by_token",
        lambda *_args, **_kwargs: existing,
    )
    monkeypatch.setattr(
        goods_expense_income_service,
        "_document_to_dict",
        lambda *_args: {"id": 91, "status": "posted"},
    )
    monkeypatch.setattr(
        goods_expense_income_service,
        "create_document",
        lambda *_args, **_kwargs: pytest.fail("نباید سند دوم ساخته شود"),
    )

    result = create_goods_income_correction(
        SimpleNamespace(),
        business_id=5,
        user_id=7,
        document_date=document_date,
        lines=lines,
        description="اصلاح فروش سریع",
        user_can_allocate=True,
        user_can_post=True,
        user_can_change_unit_cost=False,
        request_token="qs-stock-5-sale-1-12345678",
    )

    assert result == {"id": 91, "status": "posted", "idempotent_replay": True}


def test_stock_correction_rejects_reused_token_for_different_request(monkeypatch):
    from app.services import inventory_discrepancy_service as service

    existing = SimpleNamespace(
        id=91,
        extra_info={"request_fingerprint": "another-request"},
    )
    monkeypatch.setattr(service, "acquire_transaction_lock", lambda *_args: None)
    monkeypatch.setattr(
        service,
        "_find_quick_sales_correction_by_token",
        lambda *_args, **_kwargs: existing,
    )

    with pytest.raises(ApiError) as exc_info:
        create_goods_income_correction(
            SimpleNamespace(),
            business_id=5,
            user_id=7,
            document_date=date(2026, 10, 17),
            lines=[{"product_id": 11, "warehouse_id": 3, "quantity": 2}],
            description="اصلاح فروش سریع",
            user_can_allocate=True,
            user_can_post=True,
            user_can_change_unit_cost=False,
            request_token="qs-stock-5-sale-1-12345678",
        )

    assert exc_info.value.code == "STOCK_CORRECTION_REQUEST_TOKEN_REUSED"


def test_stock_correction_stores_token_and_fingerprint(monkeypatch):
    from app.services import goods_expense_income_service
    from app.services import inventory_discrepancy_service as service

    captured = {}
    monkeypatch.setattr(service, "acquire_transaction_lock", lambda *_args: None)
    monkeypatch.setattr(
        service,
        "_find_quick_sales_correction_by_token",
        lambda *_args, **_kwargs: None,
    )

    def create_document(_db, _business_id, _user_id, payload, **_kwargs):
        captured.update(payload)
        return {"id": 92, "status": "posted"}

    monkeypatch.setattr(goods_expense_income_service, "create_document", create_document)

    result = create_goods_income_correction(
        SimpleNamespace(),
        business_id=5,
        user_id=7,
        document_date=date(2026, 10, 17),
        lines=[{"product_id": 11, "warehouse_id": 3, "quantity": 2}],
        description="اصلاح فروش سریع",
        user_can_allocate=True,
        user_can_post=True,
        user_can_change_unit_cost=False,
        request_token="qs-stock-5-sale-1-12345678",
    )

    assert result["idempotent_replay"] is False
    assert captured["extra_info"]["request_token"] == "qs-stock-5-sale-1-12345678"
    assert len(captured["extra_info"]["request_fingerprint"]) == 64
