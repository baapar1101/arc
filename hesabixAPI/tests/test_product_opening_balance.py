"""تست‌های تعداد اولیه کالا در سند تراز افتتاحیه."""

from app.services.product_opening_balance_service import (
    _extract_product_ob_line,
    _maybe_sync_opening_warehouse,
    _merge_product_opening_balance_changes,
    _warehouse_id_from_line,
    opening_balance_lot_extra,
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
    assert line1.get("lot_code") is None

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


def test_opening_balance_lot_extra_stamps_allocations():
    extra = opening_balance_lot_extra(
        lot_code="L-1",
        manufacturing_date="2026-01-01",
        expiry_date="2026-06-01",
        quantity=12,
    )
    assert extra["lot_code"] == "L-1"
    assert extra["manufacturing_date"] == "2026-01-01"
    assert extra["expiry_date"] == "2026-06-01"
    assert extra["lot_allocations"][0]["quantity"] == 12


def test_opening_balance_lot_extra_empty_without_dates():
    assert opening_balance_lot_extra(quantity=5) == {}


def test_extract_product_ob_line_returns_lot_dates():
    doc = {
        "lines": [
            {
                "product_id": 10,
                "quantity": 4,
                "extra_info": {
                    "warehouse_id": 1,
                    "lot_code": "OB-9",
                    "manufacturing_date": "2026-02-01",
                    "expiry_date": "2026-08-01",
                },
            },
        ],
    }
    line = _extract_product_ob_line(doc, 10, warehouse_id=1)
    assert line is not None
    assert line["lot_code"] == "OB-9"
    assert line["manufacturing_date"] == "2026-02-01"
    assert line["expiry_date"] == "2026-08-01"


def test_merge_import_changes_keeps_lot_dates():
    merged = _merge_product_opening_balance_changes(
        [],
        [
            {
                "product_id": 1,
                "warehouse_id": 2,
                "quantity": 8,
                "cost_price": 12,
                "lot_code": "LOT-A",
                "manufacturing_date": "2026-01-10",
                "expiry_date": "2026-07-10",
            },
        ],
    )
    info = merged[0]["extra_info"]
    assert info["lot_code"] == "LOT-A"
    assert info["expiry_date"] == "2026-07-10"
    assert info["lot_allocations"][0]["lot_code"] == "LOT-A"


def test_maybe_sync_opening_warehouse_skips_when_history_exists(monkeypatch):
    called = {"sync": False}

    monkeypatch.setattr(
        "app.services.opening_balance_warehouse_sync_service.find_products_with_unrelated_posted_warehouse_history",
        lambda *args, **kwargs: {9},
    )
    monkeypatch.setattr(
        "app.services.opening_balance_warehouse_sync_service.sync_opening_balance_warehouse_documents",
        lambda *args, **kwargs: called.__setitem__("sync", True),
    )
    _maybe_sync_opening_warehouse(None, 1, 2, {"id": 3}, 9)
    assert called["sync"] is False


def test_maybe_sync_opening_warehouse_runs_without_history(monkeypatch):
    called = {"sync": False}

    monkeypatch.setattr(
        "app.services.opening_balance_warehouse_sync_service.find_products_with_unrelated_posted_warehouse_history",
        lambda *args, **kwargs: set(),
    )

    def _sync(*args, **kwargs):
        called["sync"] = True
        called["doc_id"] = args[3]
        called["product_ids"] = args[4]

    monkeypatch.setattr(
        "app.services.opening_balance_warehouse_sync_service.sync_opening_balance_warehouse_documents",
        _sync,
    )
    _maybe_sync_opening_warehouse(None, 1, 2, {"id": 33}, 9)
    assert called["sync"] is True
    assert called["doc_id"] == 33
    assert called["product_ids"] == [9]
