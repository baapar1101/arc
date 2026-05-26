from datetime import date
from decimal import Decimal
from unittest.mock import MagicMock, patch

from app.services.warehouse_service import (
    calculate_stock_count_differences,
    start_stock_count,
)


def test_calculate_stock_count_uses_server_system_quantity() -> None:
    db = MagicMock()
    with patch(
        "app.services.warehouse_service.get_physical_stock",
        return_value=Decimal("42"),
    ) as mock_stock:
        result = calculate_stock_count_differences(
            db,
            business_id=5017,
            items=[
                {
                    "product_id": 224553,
                    "warehouse_id": 8974,
                    "system_quantity": 999,
                    "physical_quantity": 50,
                }
            ],
            as_of_date=date(2026, 5, 26),
        )

    mock_stock.assert_called_once_with(db, 5017, 224553, 8974, date(2026, 5, 26))
    row = result["items"][0]
    assert row["system_quantity"] == 42.0
    assert row["physical_quantity"] == 50.0
    assert row["difference"] == 8.0
    assert row["movement"] == "in"


def test_start_stock_count_only_with_warehouse_history_filters_rows() -> None:
    db = MagicMock()
    product = MagicMock()
    product.id = 224553
    product.code = "P224553"
    product.name = "test"
    product.main_unit = "عدد"
    product.track_inventory = True

    warehouse = MagicMock()
    warehouse.id = 8974
    warehouse.code = "WH-08974"
    warehouse.name = "انبار مرکزی"

    product_query = MagicMock()
    product_query.filter.return_value = product_query
    product_query.all.return_value = [product]

    warehouse_query = MagicMock()
    warehouse_query.filter.return_value = warehouse_query
    warehouse_query.all.return_value = [warehouse]

    def _query_side(model):
        if getattr(model, "__name__", "") == "Product":
            return product_query
        return warehouse_query

    db.query.side_effect = _query_side

    with patch(
        "app.services.warehouse_service.get_warehouse_history_index",
        return_value=({224553}, {(224553, 8974)}),
    ), patch(
        "app.services.warehouse_service.get_physical_stock",
        return_value=Decimal("100"),
    ):
        with_history = start_stock_count(
            db,
            5017,
            warehouse_id=8974,
            only_with_warehouse_history=True,
        )
        _, wh_pairs = __import__(
            "app.services.warehouse_service", fromlist=["get_warehouse_history_index"]
        ).get_warehouse_history_index.return_value
        # patch returns fixed value; simulate empty history
        with patch(
            "app.services.warehouse_service.get_warehouse_history_index",
            return_value=(set(), set()),
        ):
            without_history = start_stock_count(
                db,
                5017,
                warehouse_id=8974,
                only_with_warehouse_history=True,
            )

    assert len(with_history["items"]) == 1
    assert without_history["items"] == []
