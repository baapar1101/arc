from decimal import Decimal

import pytest

from adapters.db import models
from adapters.db.models.product_variant_allocation import WarehouseLineVariantAllocation
from app.core.responses import ApiError
from app.services.product_variant_service import list_variant_balances
from app.services.warehouse_service import (
    create_manual_warehouse_document,
    post_warehouse_document,
    update_warehouse_document,
    update_warehouse_document_line,
)
from tests.test_warehouse_transfer_currency import DAY
from tests.test_warehouse_transfer_currency import transfer_db as transfer_db


@pytest.fixture
def native_db(transfer_db):
    db = transfer_db
    product = db.get(models.Product, 1)
    product.variant_mode, product.track_inventory = "inventory", True
    product.main_unit, product.secondary_unit, product.unit_conversion_factor = "carton", "each", Decimal(10)
    db.add(models.Product(id=4, business_id=1, code="OTHER", name="Other", variant_mode="inventory"))
    for vid, bid, pid in ((1, 1, 1), (2, 1, 1), (3, 1, 4), (4, 2, 2)):
        db.add(models.ProductVariant(id=vid, business_id=bid, product_id=pid, combination_key=str(vid)))
    db.commit()
    receipt = create_manual_warehouse_document(db, 1, 1, {
        "doc_type": "receipt", "document_date": DAY.isoformat(), "warehouse_id_to": 11,
        "lines": [line(1, 10), line(2, 12)],
    })
    post_warehouse_document(db, receipt.id)
    db.commit()
    return db


def line(variant, qty, unit="main", **fields):
    return {"product_id": 1, "quantity": qty, "allocations": [{"variant_id": variant, "quantity": qty}],
            "extra_info": {"unit": unit, "unit_cost": 100}, **fields}


def transfer(db, entries):
    doc = create_manual_warehouse_document(db, 1, 1, {
        "doc_type": "transfer", "document_date": DAY.isoformat(),
        "warehouse_id_from": 11, "warehouse_id_to": 12, "lines": entries,
    })
    db.commit()
    return doc


def allocations(db, did):
    return sorted((r.movement, r.quantity, a.variant_id, a.quantity) for r, a in
                  db.query(models.WarehouseDocumentLine, WarehouseLineVariantAllocation).join(
                      WarehouseLineVariantAllocation,
                      WarehouseLineVariantAllocation.warehouse_document_line_id == models.WarehouseDocumentLine.id,
                  ).filter(models.WarehouseDocumentLine.warehouse_document_id == did))


@pytest.mark.parametrize("unit,quantities", [("main", (2, 3)), ("each", (20, 30))])
@pytest.mark.parametrize("edit", [False, True])
def test_official_transfer_preserves_main_unit_allocations_and_balances(native_db, unit, quantities, edit):
    db = native_db
    doc = transfer(db, [line(1, quantities[0], unit), line(2, quantities[1], unit)])
    if edit:
        update_warehouse_document(db, 1, doc.id, 1, {"lines": [
            line(vid, qty, unit, movement=movement, warehouse_id=wid)
            for vid, qty in zip((1, 2), quantities, strict=True)
            for movement, wid in (("out", 11), ("in", 12))
        ]})
        db.commit()
    expected = sorted((movement, q, vid, q) for vid, q in ((1, 2), (2, 3)) for movement in ("in", "out"))
    assert allocations(db, doc.id) == expected
    post_warehouse_document(db, doc.id)
    db.commit()
    db.expire_all()
    assert allocations(db, doc.id) == expected
    for wid, expected_balances in ((11, {1: 8, 2: 9}), (12, {1: 2, 2: 3})):
        assert {r["variant_id"]: Decimal(r["quantity"]) for r in list_variant_balances(db, 1, 1, wid)} == expected_balances
    assert doc.status == "posted"


@pytest.mark.parametrize("vid,allocated,code", [(999, 2, "VARIANT_NOT_FOUND"), (3, 2, "VARIANT_NOT_FOUND"),
                                                (4, 2, "VARIANT_NOT_FOUND"), (1, 1, "VARIANT_ALLOCATION_MISMATCH")])
def test_transfer_rejects_invalid_variant_or_quantity(native_db, vid, allocated, code):
    db = native_db
    payload = line(vid, 2)
    payload["allocations"][0]["quantity"] = allocated
    with pytest.raises(ApiError) as error:
        transfer(db, [payload])
    assert error.value.code == code
    db.rollback()
    assert {r["variant_id"]: Decimal(r["quantity"]) for r in list_variant_balances(db, 1, 1, 11)} == {1: 10, 2: 12}


def test_draft_edit_cannot_change_only_one_side_variant(native_db):
    db = native_db
    doc = transfer(db, [line(1, 2), line(2, 3)])
    before = allocations(db, doc.id)
    with pytest.raises(ApiError) as error:
        update_warehouse_document(db, 1, doc.id, 1, {"lines": [
            line(1, 2, movement="out", warehouse_id=11), line(2, 2, movement="in", warehouse_id=12),
        ]})
    assert error.value.code == "TRANSFER_VARIANT_MISMATCH"
    db.rollback()
    db.expire_all()
    assert doc.status == "draft" and allocations(db, doc.id) == before


def test_transfer_rollback_restores_balances_and_accounting(native_db):
    db = native_db
    doc = transfer(db, [line(1, 2), line(2, 3)])
    post_warehouse_document(db, doc.id)
    db.rollback()
    db.expire_all()
    assert doc.status == "draft"
    assert db.query(models.Document).count() == db.query(models.DocumentLine).count() == 0
    assert {r["variant_id"]: Decimal(r["quantity"]) for r in list_variant_balances(db, 1, 1, 11)} == {1: 10, 2: 12}
    assert list_variant_balances(db, 1, 1, 12) == []
    post_warehouse_document(db, doc.id)
    db.commit()
    assert doc.status == "posted"


def test_draft_line_edits_validate_allocations_before_transfer_post(native_db):
    db = native_db
    doc = transfer(db, [line(1, 2)])
    rows = db.query(models.WarehouseDocumentLine).filter_by(warehouse_document_id=doc.id).all()
    update_warehouse_document_line(db, 1, doc.id, rows[0].id, line(1, 40, "each"))
    db.commit()
    with pytest.raises(ApiError) as error:
        post_warehouse_document(db, doc.id)
    assert error.value.code == "TRANSFER_VARIANT_MISMATCH"
    db.rollback()
    update_warehouse_document_line(db, 1, doc.id, rows[1].id, line(1, 40, "each"))
    db.commit()
    assert allocations(db, doc.id) == [("in", 4, 1, 4), ("out", 4, 1, 4)]
    post_warehouse_document(db, doc.id)
    db.commit()
    assert {r["variant_id"]: Decimal(r["quantity"]) for r in list_variant_balances(db, 1, 1, 11)} == {1: 6, 2: 12}
