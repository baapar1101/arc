"""Regression: product tax fields must persist on update."""

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


def test_product_repository_update_persists_tax_fields() -> None:
    obj = SimpleNamespace(
        tax_type_id=None,
        tax_code=None,
        tax_unit_id=None,
        sales_tax_rate=None,
        purchase_tax_rate=None,
        is_sales_taxable=False,
        is_purchase_taxable=False,
    )
    _apply_update(
        obj,
        tax_type_id=5,
        tax_code="1234567890123",
        tax_unit_id=3,
        sales_tax_rate=Decimal("9"),
        is_sales_taxable=True,
    )
    assert obj.tax_type_id == 5
    assert obj.tax_code == "1234567890123"
    assert obj.tax_unit_id == 3
    assert obj.sales_tax_rate == Decimal("9")
    assert obj.is_sales_taxable is True


def test_product_repository_update_can_clear_tax_fields() -> None:
    obj = SimpleNamespace(
        tax_type_id=5,
        tax_code="old",
        tax_unit_id=3,
        sales_tax_rate=Decimal("9"),
        purchase_tax_rate=Decimal("9"),
    )
    _apply_update(
        obj,
        tax_type_id=None,
        tax_code=None,
        tax_unit_id=None,
        sales_tax_rate=None,
        purchase_tax_rate=None,
    )
    assert obj.tax_type_id is None
    assert obj.tax_code is None
    assert obj.tax_unit_id is None
    assert obj.sales_tax_rate is None
    assert obj.purchase_tax_rate is None
