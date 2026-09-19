"""تست‌های کمکی ایمپورت اکسل — تعداد اولیه و انبار."""

from types import SimpleNamespace

from app.services.product_excel_import_opening_balance import (
    OPENING_BALANCE_COST_KEY,
    OPENING_BALANCE_QUANTITY_KEY,
    WarehouseImportIndex,
    opening_balance_columns_mapped,
    prepare_opening_balance_for_import_row,
    resolve_import_default_warehouse,
)


def _warehouse(wid: int, code: str, name: str, is_default: bool = False):
    return SimpleNamespace(id=wid, code=code, name=name, is_default=is_default)


def test_opening_balance_columns_mapped():
    assert opening_balance_columns_mapped({"opening_balance_quantity"})
    assert opening_balance_columns_mapped({"opening_balance_cost_price"})
    assert not opening_balance_columns_mapped({"track_inventory"})


def test_warehouse_index_resolve_by_code():
    idx = WarehouseImportIndex([_warehouse(3, "WH1", "انبار اصلی", True)])
    wid, err, preview = idx.resolve(warehouse_code="WH1")
    assert err is None
    assert wid == 3
    assert preview["by"] == "code"


def test_warehouse_index_default():
    idx = WarehouseImportIndex([_warehouse(5, "A", "Main", True)])
    assert idx.default_warehouse_id() == 5


def test_resolve_import_default_warehouse_sets_item():
    idx = WarehouseImportIndex([_warehouse(2, "W2", "Store")])
    item = {"warehouse_code": "W2"}
    errors, preview = resolve_import_default_warehouse(
        item, {"warehouse_code"}, idx
    )
    assert errors == []
    assert item["default_warehouse_id"] == 2
    assert preview["default_warehouse_id"] == 2


def test_prepare_opening_balance_requires_track_inventory():
    idx = WarehouseImportIndex([_warehouse(1, "W", "W", True)])
    item = {
        "item_type": "کالا",
        "track_inventory": False,
        OPENING_BALANCE_QUANTITY_KEY: 5,
    }
    ob, errors, warnings, preview = prepare_opening_balance_for_import_row(
        item=item,
        mapped_keys={OPENING_BALANCE_QUANTITY_KEY},
        business_id=1,
        db=None,  # type: ignore[arg-type]
        can_edit_opening_balance=True,
        is_update=False,
        existing_product=None,
        warehouse_index=idx,
    )
    assert ob is None
    assert any("کنترل موجودی" in e for e in errors)


def test_prepare_opening_balance_requires_permission():
    idx = WarehouseImportIndex([_warehouse(1, "W", "W", True)])
    item = {
        "item_type": "کالا",
        "track_inventory": True,
        OPENING_BALANCE_QUANTITY_KEY: 5,
        "default_warehouse_id": 1,
    }
    ob, errors, warnings, preview = prepare_opening_balance_for_import_row(
        item=item,
        mapped_keys={OPENING_BALANCE_QUANTITY_KEY},
        business_id=1,
        db=None,  # type: ignore[arg-type]
        can_edit_opening_balance=False,
        is_update=False,
        existing_product=None,
        warehouse_index=idx,
    )
    assert ob is None
    assert any("دسترسی" in e for e in errors)
