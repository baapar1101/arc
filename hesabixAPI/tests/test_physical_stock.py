from decimal import Decimal
from unittest.mock import MagicMock

from app.services.warehouse_service import (
    _include_inventory_stock_row,
    get_physical_stock_bulk,
)


def test_physical_stock_bulk_sums_posted_movements() -> None:
    line_in = MagicMock()
    line_in.product_id = 1
    line_in.quantity = Decimal("100")
    line_in.movement = "in"

    line_out = MagicMock()
    line_out.product_id = 1
    line_out.quantity = Decimal("40")
    line_out.movement = "out"

    doc = MagicMock()

    db = MagicMock()
    db.query.return_value.join.return_value.filter.return_value.all.return_value = [
        (line_in, doc),
        (line_out, doc),
    ]

    result = get_physical_stock_bulk(db, business_id=10, product_ids=[1])
    assert result[1] == Decimal("60")


def test_physical_stock_bulk_filters_by_warehouse_id() -> None:
    line = MagicMock()
    line.product_id = 5
    line.quantity = Decimal("30")
    line.movement = "in"

    doc = MagicMock()

    db = MagicMock()
    base = db.query.return_value.join.return_value.filter.return_value
    base.filter.return_value.all.return_value = [(line, doc)]

    result = get_physical_stock_bulk(db, business_id=10, product_ids=[5], warehouse_id=100)
    assert result[5] == Decimal("30")
    base.filter.assert_called_once()


def test_include_inventory_stock_row_with_zero_and_history() -> None:
    assert _include_inventory_stock_row(
        stock=Decimal(0),
        include_zero=False,
        has_warehouse_history=True,
    )


def test_include_inventory_stock_row_hides_zero_without_history() -> None:
    assert not _include_inventory_stock_row(
        stock=Decimal(0),
        include_zero=False,
        has_warehouse_history=False,
    )


def test_include_inventory_stock_row_include_zero_flag() -> None:
    assert _include_inventory_stock_row(
        stock=Decimal(0),
        include_zero=True,
        has_warehouse_history=False,
    )
