from types import SimpleNamespace

from app.services.inventory_discrepancy_service import (
    _correction_lines_by_case_line,
    _serialize,
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
