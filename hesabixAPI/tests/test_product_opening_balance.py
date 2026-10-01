"""تست‌های تعداد اولیه کالا در سند تراز افتتاحیه."""

from app.services.product_opening_balance_service import (
    _extract_product_ob_line,
    _merge_product_opening_balance_changes,
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


def test_merge_import_changes_preserves_unrelated_lines_and_moves_warehouse():
    existing = [
        {
            "product_id": 10,
            "quantity": 3,
            "extra_info": {"warehouse_id": 1, "movement": "in", "cost_price": 200},
            "description": "old",
        },
        {
            "product_id": 20,
            "quantity": 9,
            "extra_info": {"warehouse_id": 2, "movement": "in"},
            "description": "keep",
        },
    ]
    merged = _merge_product_opening_balance_changes(
        existing,
        [
            {
                "product_id": 10,
                "product_name": "A",
                "previous_warehouse_id": 1,
                "warehouse_id": 3,
                "quantity": 7,
                "cost_price": 250,
            },
            {
                "product_id": 30,
                "product_name": "B",
                "warehouse_id": 4,
                "quantity": 2,
                "cost_price": 0,
            },
        ],
    )
    by_key = {
        (int(line["product_id"]), int(line["extra_info"]["warehouse_id"])): line
        for line in merged
    }
    assert (10, 1) not in by_key
    assert by_key[(10, 3)]["quantity"] == 7
    assert by_key[(10, 3)]["extra_info"]["cost_price"] == 250
    assert by_key[(20, 2)]["description"] == "keep"
    assert by_key[(30, 4)]["quantity"] == 2


def test_merge_import_changes_last_duplicate_wins_without_growing_lines():
    merged = _merge_product_opening_balance_changes(
        [],
        [
            {"product_id": 1, "warehouse_id": 2, "quantity": 3, "cost_price": 10},
            {"product_id": 1, "warehouse_id": 2, "quantity": 8, "cost_price": 12},
        ],
    )
    assert len(merged) == 1
    assert merged[0]["quantity"] == 8
    assert merged[0]["extra_info"]["cost_price"] == 12
