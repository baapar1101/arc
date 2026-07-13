"""تست‌های تعداد اولیه کالا در سند تراز افتتاحیه."""

from app.services.product_opening_balance_service import (
    _extract_product_ob_line,
    _warehouse_id_from_line,
)


def test_warehouse_id_from_line():
    assert _warehouse_id_from_line({"extra_info": {"warehouse_id": 5}}) == 5
    assert _warehouse_id_from_line({"extra_info": {}}) is None


def test_extract_product_ob_line_matches_warehouse():
    doc = {
        "lines": [
            {
                "product_id": 10,
                "quantity": 3,
                "extra_info": {"warehouse_id": 1, "cost_price": 200},
            },
            {
                "product_id": 10,
                "quantity": 7,
                "extra_info": {"warehouse_id": 2, "cost_price": 150},
            },
        ],
    }
    line1 = _extract_product_ob_line(doc, 10, warehouse_id=1)
    assert line1 is not None
    assert line1["quantity"] == 3
    assert line1["cost_price"] == 200
    assert line1["warehouse_id"] == 1

    line2 = _extract_product_ob_line(doc, 10, warehouse_id=2)
    assert line2 is not None
    assert line2["quantity"] == 7

    assert _extract_product_ob_line(doc, 10, warehouse_id=99) is None


def test_extract_product_ob_line_without_warehouse_returns_first():
    doc = {
        "lines": [
            {
                "product_id": 10,
                "quantity": 5,
                "extra_info": {"warehouse_id": 3, "cost_price": 100},
            },
        ],
    }
    line = _extract_product_ob_line(doc, 10)
    assert line is not None
    assert line["quantity"] == 5
