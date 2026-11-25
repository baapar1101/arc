"""Inventory unit conversion: carton/piece contract and historical warehouse safety."""

from datetime import date
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest

from app.core.responses import ApiError
from app.services.invoice_service import (
    _invoice_line_qty_main,
    _main_cost_to_line_unit,
    collect_stock_shortages,
)
from app.services.invoice_unit_conversion_service import (
    inventory_quantity_to_main,
    is_secondary_line_unit,
    quantity_line_to_main,
    quantity_main_to_line,
    stamp_inventory_quantity_as_main,
    warehouse_payload_quantity_to_main,
)
from adapters.db.models.product import Product
from app.services.purchase_accounting_service import (
    compute_warehouse_receipt_inventory_amount,
)
from app.services.warehouse_service import (
    _compute_line_quantities_core,
    _warehouse_qty_in_invoice_line_unit,
    get_physical_stock_bulk,
    validate_invoice_warehouse_lines_quantities,
)


def _carton_product(**kwargs):
    data = dict(
        main_unit="کارتن",
        secondary_unit="عدد",
        unit_conversion_factor=Decimal("10"),
    )
    data.update(kwargs)
    return SimpleNamespace(**data)


def test_aliases_main_secondary_match_product_labels() -> None:
    product = _carton_product()
    assert is_secondary_line_unit(product, None) is False
    assert is_secondary_line_unit(product, "main") is False
    assert is_secondary_line_unit(product, "کارتن") is False
    assert is_secondary_line_unit(product, "secondary") is True
    assert is_secondary_line_unit(product, "عدد") is True


def test_unknown_unit_is_strict_on_write_and_lenient_on_read() -> None:
    product = _carton_product()
    with pytest.raises(ApiError):
        is_secondary_line_unit(product, "کیلو")
    assert is_secondary_line_unit(product, "کیلو", strict=False) is False


def test_eleven_pieces_are_one_point_one_cartons() -> None:
    product = _carton_product()
    assert quantity_line_to_main(Decimal("11"), product, "عدد") == Decimal("1.1")
    assert quantity_main_to_line(Decimal("1.1"), product, "عدد") == Decimal("11.0")


def test_historical_warehouse_without_unit_stays_main() -> None:
    product = _carton_product()
    assert inventory_quantity_to_main(Decimal("10"), product, None) == Decimal("10")
    assert inventory_quantity_to_main(Decimal("10"), product, {}) == Decimal("10")


def test_legacy_invoice_copied_warehouse_line_converts() -> None:
    product = _carton_product()
    extra = {"unit": "عدد"}
    assert inventory_quantity_to_main(Decimal("11"), product, extra) == Decimal("1.1")


def test_stamped_warehouse_line_does_not_double_convert() -> None:
    product = _carton_product()
    qty_main, stamped = warehouse_payload_quantity_to_main(
        product, Decimal("11"), {"unit": "عدد"}
    )
    assert qty_main == Decimal("1.1")
    assert stamped["inventory_quantity_unit"] == "main"
    assert stamped["unit"] == "کارتن"
    assert stamped["source_line_unit"] == "عدد"
    assert inventory_quantity_to_main(qty_main, product, stamped) == Decimal("1.1")


def test_stamp_then_payload_edit_keeps_main_quantity() -> None:
    product = _carton_product()
    stamped = stamp_inventory_quantity_as_main({"unit": "کارتن"}, product)
    qty_main, _ = warehouse_payload_quantity_to_main(product, Decimal("8"), stamped)
    assert qty_main == Decimal("8")


def test_physical_stock_converts_legacy_secondary_issue() -> None:
    product = _carton_product(id=1)
    line_in = SimpleNamespace(
        product_id=1, quantity=Decimal("10"), movement="in", extra_info=None
    )
    line_out = SimpleNamespace(
        product_id=1,
        quantity=Decimal("1"),
        movement="out",
        extra_info={"unit": "عدد"},
    )
    db = MagicMock()
    query = db.query.return_value
    join_filter = query.join.return_value.filter.return_value
    join_filter.all.return_value = [(line_in, MagicMock()), (line_out, MagicMock())]
    query.filter.return_value.all.return_value = [product]

    result = get_physical_stock_bulk(db, business_id=10, product_ids=[1])
    assert result[1] == Decimal("9.9")


def test_physical_stock_mock_without_extra_dict_is_unchanged() -> None:
    line_in = MagicMock()
    line_in.product_id = 1
    line_in.quantity = Decimal("100")
    line_in.movement = "in"
    line_out = MagicMock()
    line_out.product_id = 1
    line_out.quantity = Decimal("40")
    line_out.movement = "out"
    db = MagicMock()
    db.query.return_value.join.return_value.filter.return_value.all.return_value = [
        (line_in, MagicMock()),
        (line_out, MagicMock()),
    ]
    result = get_physical_stock_bulk(db, business_id=10, product_ids=[1])
    assert result[1] == Decimal("60")


def test_fulfillment_remaining_stays_in_invoice_line_unit() -> None:
    product = _carton_product(id=1)
    item = SimpleNamespace(
        id=10,
        product_id=1,
        quantity=Decimal("11"),
        extra_info={"unit": "عدد"},
    )
    new_wh_line = SimpleNamespace(
        movement="out",
        quantity=Decimal("1.1"),
        product_id=1,
        extra_info={
            "invoice_item_line_id": 10,
            "inventory_quantity_unit": "main",
            "unit": "کارتن",
        },
    )
    old_wh_line = SimpleNamespace(
        movement="out",
        quantity=Decimal("11"),
        product_id=1,
        extra_info={"invoice_item_line_id": 10, "unit": "عدد"},
    )
    new_doc = SimpleNamespace(status="posted", lines=[new_wh_line])
    old_doc = SimpleNamespace(status="posted", lines=[old_wh_line])

    new_qty = _compute_line_quantities_core(
        "invoice_sales", [item], [new_doc], products_by_id={1: product}
    )
    old_qty = _compute_line_quantities_core(
        "invoice_sales", [item], [old_doc], products_by_id={1: product}
    )
    assert new_qty[0]["required_quantity"] == 11.0
    assert new_qty[0]["processed_quantity"] == 11.0
    assert new_qty[0]["remaining_quantity"] == 0.0
    assert old_qty[0]["processed_quantity"] == 11.0
    assert old_qty[0]["remaining_quantity"] == 0.0


def test_stock_check_converts_eleven_pieces_against_ten_cartons() -> None:
    product = _carton_product(id=1, name="آبی‌میوه", code="A")
    db = MagicMock()
    query = db.query.return_value
    query.filter.return_value.all.side_effect = [
        [SimpleNamespace(
            id=1,
            name="آبی‌میوه",
            code="A",
            main_unit="کارتن",
            secondary_unit="عدد",
            unit_conversion_factor=Decimal("10"),
        )],
        [SimpleNamespace(id=9, name="انبار اصلی")],
        [SimpleNamespace(id=1, inventory_mode="bulk")],
    ]
    lines = [{
        "product_id": 1,
        "quantity": 11,
        "extra_info": {"warehouse_id": 9, "unit": "عدد"},
    }]
    with patch(
        "app.services.invoice_service._compute_available_stock",
        return_value=Decimal("10"),
    ):
        shortages = collect_stock_shortages(db, 17, date(2026, 10, 3), lines)
    assert shortages == []


def test_stock_check_one_hundred_one_pieces_is_short_against_ten_cartons() -> None:
    db = MagicMock()
    query = db.query.return_value
    query.filter.return_value.all.side_effect = [
        [SimpleNamespace(
            id=1,
            name="آبی‌میوه",
            code="A",
            main_unit="کارتن",
            secondary_unit="عدد",
            unit_conversion_factor=Decimal("10"),
        )],
        [SimpleNamespace(id=9, name="انبار اصلی")],
        [SimpleNamespace(id=1, inventory_mode="bulk")],
    ]
    lines = [{
        "product_id": 1,
        "quantity": 101,
        "extra_info": {"warehouse_id": 9, "unit": "عدد"},
    }]
    with patch(
        "app.services.invoice_service._compute_available_stock",
        return_value=Decimal("10"),
    ):
        shortages = collect_stock_shortages(db, 17, date(2026, 10, 3), lines)
    assert len(shortages) == 1
    assert shortages[0]["requested_quantity"] == 10.1
    assert shortages[0]["available_quantity"] == 10.0
    assert abs(shortages[0]["shortage_quantity"] - 0.1) < 1e-9


def test_profit_converts_carton_cost_to_piece_line_unit() -> None:
    product = _carton_product(base_purchase_price=Decimal("100000"))
    line = SimpleNamespace(quantity=Decimal("11"), extra_info={"unit": "عدد"})
    assert _invoice_line_qty_main(product, line) == Decimal("1.1")
    assert _main_cost_to_line_unit(Decimal("100000"), product, line) == Decimal("10000")
    assert Decimal("11") * _main_cost_to_line_unit(Decimal("100000"), product, line) == Decimal("110000")


def test_issuing_one_piece_from_ten_stamped_cartons_leaves_nine_point_nine() -> None:
    product = _carton_product(id=1)
    line_in = SimpleNamespace(
        product_id=1,
        quantity=Decimal("10"),
        movement="in",
        extra_info={"inventory_quantity_unit": "main", "unit": "کارتن"},
    )
    line_out = SimpleNamespace(
        product_id=1,
        quantity=Decimal("1"),
        movement="out",
        extra_info={"unit": "عدد"},
    )
    db = MagicMock()
    query = db.query.return_value
    join_filter = query.join.return_value.filter.return_value
    join_filter.all.return_value = [(line_in, MagicMock()), (line_out, MagicMock())]
    query.filter.return_value.all.return_value = [product]

    result = get_physical_stock_bulk(db, business_id=10, product_ids=[1])
    assert result[1] == Decimal("9.9")


def test_stamped_warehouse_qty_converts_back_to_invoice_piece_unit() -> None:
    product = _carton_product()
    stamped = {
        "inventory_quantity_unit": "main",
        "unit": "کارتن",
        "source_line_unit": "عدد",
    }
    assert _warehouse_qty_in_invoice_line_unit(
        Decimal("1.1"), product, stamped, "عدد"
    ) == Decimal("11.0")
    assert _warehouse_qty_in_invoice_line_unit(
        Decimal("11"), product, {"unit": "عدد"}, "عدد"
    ) == Decimal("11")


def test_validate_allows_stamped_main_qty_equal_to_piece_remaining() -> None:
    product = _carton_product(id=1)
    lines = [{
        "product_id": 1,
        "quantity": Decimal("1.1"),
        "extra_info": {
            "invoice_item_line_id": 10,
            "inventory_quantity_unit": "main",
            "unit": "کارتن",
            "source_line_unit": "عدد",
        },
    }]
    remaining = [{
        "invoice_item_line_id": 10,
        "product_id": 1,
        "unit": "عدد",
        "remaining_quantity": 11.0,
    }]
    db = MagicMock()
    db.query.return_value.filter.return_value.all.return_value = [product]
    with patch(
        "app.services.warehouse_service.compute_invoice_line_quantities",
        return_value=remaining,
    ):
        validate_invoice_warehouse_lines_quantities(db, 1, SimpleNamespace(), lines)


def test_validate_rejects_stamped_main_qty_that_matches_piece_remaining_number() -> None:
    product = _carton_product(id=1)
    lines = [{
        "product_id": 1,
        "quantity": Decimal("11"),
        "extra_info": {
            "invoice_item_line_id": 10,
            "inventory_quantity_unit": "main",
            "unit": "کارتن",
            "source_line_unit": "عدد",
        },
    }]
    remaining = [{
        "invoice_item_line_id": 10,
        "product_id": 1,
        "unit": "عدد",
        "remaining_quantity": 11.0,
    }]
    db = MagicMock()
    db.query.return_value.filter.return_value.all.return_value = [product]
    with patch(
        "app.services.warehouse_service.compute_invoice_line_quantities",
        return_value=remaining,
    ):
        with pytest.raises(ApiError) as exc:
            validate_invoice_warehouse_lines_quantities(db, 1, SimpleNamespace(), lines)
    assert exc.value.code == "QUANTITY_EXCEEDS_REMAINING"


def test_grni_amount_multiplies_main_qty_by_converted_line_cost() -> None:
    product = _carton_product(id=1, track_inventory=True, base_purchase_price=Decimal("100000"))
    invoice_line = SimpleNamespace(id=10, extra_info={"unit": "عدد", "unit_price": 10000})
    wh_line = SimpleNamespace(
        movement="in",
        quantity=Decimal("1.1"),
        product_id=1,
        extra_info={
            "invoice_item_line_id": 10,
            "inventory_quantity_unit": "main",
            "unit": "کارتن",
            "source_line_unit": "عدد",
            "unit_price": 10000,
        },
    )

    def _query(model):
        q = MagicMock()
        if model is Product:
            q.filter.return_value.first.return_value = product
        else:
            q.filter.return_value.first.return_value = invoice_line
        return q

    db = MagicMock()
    db.query.side_effect = _query
    amount = compute_warehouse_receipt_inventory_amount(db, 1, [wh_line])
    assert amount == Decimal("110000.0")


def test_grni_amount_uses_source_line_unit_when_invoice_row_missing() -> None:
    product = _carton_product(id=1, track_inventory=True, base_purchase_price=Decimal("100000"))
    wh_line = SimpleNamespace(
        movement="in",
        quantity=Decimal("1.1"),
        product_id=1,
        extra_info={
            "invoice_item_line_id": 10,
            "inventory_quantity_unit": "main",
            "unit": "کارتن",
            "source_line_unit": "عدد",
            "unit_price": 10000,
        },
    )

    def _query(model):
        q = MagicMock()
        q.filter.return_value.first.return_value = product if model is Product else None
        return q

    db = MagicMock()
    db.query.side_effect = _query
    amount = compute_warehouse_receipt_inventory_amount(db, 1, [wh_line])
    assert amount == Decimal("110000.0")
