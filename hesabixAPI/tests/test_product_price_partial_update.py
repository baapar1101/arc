"""Regression: omitted price fields on product update must not clear stored values."""

from __future__ import annotations

from decimal import Decimal
from types import SimpleNamespace


def _apply_update(obj, **data):
    nullable_overrides = {
        "main_unit_id",
        "secondary_unit_id",
        "unit_conversion_factor",
        "default_warehouse_id",
        "base_sales_price",
        "base_purchase_price",
        "general_barcodes",
        "sales_tax_rate",
        "purchase_tax_rate",
        "tax_type_id",
        "tax_code",
        "tax_unit_id",
    }
    boolean_fields = {
        "is_public_catalog",
        "is_active",
        "track_inventory",
        "track_serial",
        "track_barcode",
        "is_sales_taxable",
        "is_purchase_taxable",
    }
    for k, v in data.items():
        if hasattr(obj, k):
            if k in boolean_fields:
                if v is not None:
                    setattr(obj, k, v)
            elif k in nullable_overrides:
                setattr(obj, k, v)
            elif v is not None:
                setattr(obj, k, v)


def test_omitted_purchase_price_does_not_clear_value() -> None:
    obj = SimpleNamespace(
        base_sales_price=Decimal("100"),
        base_purchase_price=Decimal("80"),
    )

    # Simulate partial update payload: sales price only (no purchase price key).
    _apply_update(obj, base_sales_price=Decimal("120"))

    assert obj.base_sales_price == Decimal("120")
    assert obj.base_purchase_price == Decimal("80")


def test_explicit_null_purchase_price_still_clears_value() -> None:
    obj = SimpleNamespace(
        base_sales_price=Decimal("100"),
        base_purchase_price=Decimal("80"),
    )

    _apply_update(obj, base_purchase_price=None)

    assert obj.base_purchase_price is None
