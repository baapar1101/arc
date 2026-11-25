"""تست منطق اختلافی رسید/حواله موجودی افتتاحیه."""

from decimal import Decimal

from app.services.opening_balance_warehouse_sync_service import (
    _group_delta_lines,
    build_opening_balance_warehouse_deltas,
)


def test_first_import_creates_full_receipt_delta() -> None:
    desired = {(10, 1): Decimal("10")}
    assert build_opening_balance_warehouse_deltas(desired, {}) == {
        (10, 1): Decimal("10")
    }


def test_repeating_same_import_is_idempotent() -> None:
    desired = {(10, 1): Decimal("10")}
    linked = {(10, 1): Decimal("10")}
    assert build_opening_balance_warehouse_deltas(desired, linked) == {}


def test_quantity_increase_and_decrease_are_delta_only() -> None:
    desired = {(10, 1): Decimal("15"), (20, 1): Decimal("7")}
    linked = {(10, 1): Decimal("10"), (20, 1): Decimal("10")}
    assert build_opening_balance_warehouse_deltas(desired, linked) == {
        (10, 1): Decimal("5"),
        (20, 1): Decimal("-3"),
    }


def test_warehouse_move_becomes_issue_and_receipt() -> None:
    desired = {(10, 2): Decimal("8")}
    linked = {(10, 1): Decimal("8")}
    deltas = build_opening_balance_warehouse_deltas(desired, linked)
    assert deltas == {
        (10, 1): Decimal("-8"),
        (10, 2): Decimal("8"),
    }

    receipts, issues = _group_delta_lines(deltas, {})
    assert receipts[2][0]["product_id"] == 10
    assert receipts[2][0]["quantity"] == Decimal("8")
    assert issues[1][0]["product_id"] == 10
    assert issues[1][0]["quantity"] == Decimal("8")


def test_lines_are_grouped_by_warehouse_not_by_product() -> None:
    deltas = {
        (1, 5): Decimal("2"),
        (2, 5): Decimal("3"),
        (3, 6): Decimal("4"),
    }
    receipts, issues = _group_delta_lines(deltas, {})
    assert issues == {}
    assert len(receipts) == 2
    assert len(receipts[5]) == 2
    assert len(receipts[6]) == 1


def test_receipt_delta_stamps_lot_quantity_as_delta() -> None:
    deltas = {(10, 1): Decimal("5")}
    lots = {
        (10, 1): {
            "lot_code": "OB-1",
            "manufacturing_date": "2026-01-01",
            "expiry_date": "2026-12-01",
            "lot_allocations": [
                {
                    "lot_code": "OB-1",
                    "manufacturing_date": "2026-01-01",
                    "expiry_date": "2026-12-01",
                    "quantity": 15,
                }
            ],
        }
    }
    receipts, issues = _group_delta_lines(deltas, {}, lots)
    assert issues == {}
    extra = receipts[1][0]["extra_info"]
    assert extra["lot_code"] == "OB-1"
    assert extra["lot_allocations"][0]["quantity"] == 5.0
    assert receipts[1][0]["lot_allocations"][0]["quantity"] == 5.0
