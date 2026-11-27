from datetime import timedelta

import pytest

from adapters.db import models
from adapters.db.models.product_variant_allocation import WarehouseLineVariantAllocation
from app.core.responses import ApiError
from app.services.invoice_service import _compute_available_stock
from app.services.opening_balance_warehouse_sync_service import (
    sync_opening_balance_warehouse_documents as synchronize,
)
from app.services.variant_inventory_service import compute_available_variant_stock
from app.services.warehouse_service import get_physical_stock
from tests.test_opening_variant_sync import DAY, payload, save
from tests.test_opening_variant_sync import opening_db as opening_db
from tests.test_warehouse_transfer_currency import transfer_db as transfer_db


@pytest.mark.parametrize("unit", ["main", "each"])
def test_opening_is_counted_once_before_and_after_warehouse_mirror(opening_db, unit):
    db = opening_db
    did = save(db, payload(unit=unit))
    for mirrored in (False, True):
        if mirrored:
            synchronize(db, 1, 1, did, [1])
            db.commit()
        quantities = [compute_available_variant_stock(db, 1, 1, 11, vid, DAY) for vid in (1, 2)]
        assert quantities == [8, 12]
        assert _compute_available_stock(db, 1, 1, 11, DAY) == sum(quantities) == 20
        assert compute_available_variant_stock(db, 1, 1, 12, 1, DAY) == 0
        assert compute_available_variant_stock(db, 2, 1, 11, 1, DAY) == 0
        assert compute_available_variant_stock(db, 1, 1, 11, 1, DAY - timedelta(days=1)) == 0
        assert compute_available_variant_stock(db, 1, 1, 11, 1, DAY, exclude_document_id=did) == 0


def legacy_opening(db):
    product = db.get(models.Product, 1)
    product.variant_mode = "none"
    data = payload((6, 4), unit="each")
    del data["inventory_lines"][0]["allocations"]
    did = save(db, data)
    synchronize(db, 1, 1, did, [1])
    db.commit()
    return did


def warehouse_movement(db, doc_type, lines, *, status="posted", warehouse=11, origin=None):
    doc = models.WarehouseDocument(
        business_id=1,
        doc_type=doc_type,
        status=status,
        document_date=DAY,
        code=f"stock-{db.query(models.WarehouseDocument).count()}",
        source_type="manual",
        warehouse_id_from=warehouse,
        warehouse_id_to=warehouse,
        extra_info=origin,
    )
    db.add(doc)
    db.flush()
    for movement, quantity, variants in lines:
        line = models.WarehouseDocumentLine(
            warehouse_document_id=doc.id,
            product_id=1,
            warehouse_id=warehouse,
            movement=movement,
            quantity=quantity,
        )
        db.add(line)
        db.flush()
        db.add_all(
            WarehouseLineVariantAllocation(
                business_id=1,
                product_id=1,
                warehouse_document_line_id=line.id,
                variant_id=variant_id,
                quantity=qty,
            )
            for variant_id, qty in variants
        )
    db.commit()
    return doc.id


def conversion(db, stock=10, splits=((1, 6), (2, 4)), **kwargs):
    db.get(models.Product, 1).variant_mode = "inventory"
    return warehouse_movement(
        db,
        "adjustment",
        [("out", stock, []), ("in", stock, splits)],
        origin={"system_origin": "variant_allocation", "product_id": 1},
        **kwargs,
    )


@pytest.mark.parametrize("prior_issue", [0, 3])
def test_legacy_opening_contributes_once_via_proven_conversion(opening_db, prior_issue):
    db = opening_db
    legacy_opening(db)
    if prior_issue:
        warehouse_movement(db, "issue", [("out", prior_issue, [])])
    remaining = 10 - prior_issue
    conversion(db, remaining, ((1, 6 - prior_issue), (2, 4)))

    assert [compute_available_variant_stock(db, 1, 1, 11, vid, DAY) for vid in (1, 2)] == [
        6 - prior_issue,
        4,
    ]
    assert compute_available_variant_stock(db, 1, 1, 12, 1, DAY) == 0
    assert compute_available_variant_stock(db, 1, 1, None, 2, DAY) == 4
    assert (
        _compute_available_stock(db, 1, 1, 11, DAY)
        == get_physical_stock(db, 1, 1, 11, DAY)
        == remaining
    )


@pytest.mark.parametrize(
    "case",
    [
        "missing",
        "unlinked",
        "draft",
        "cancelled",
        "wrong_warehouse",
        "partial",
        "unallocated",
        "duplicate",
        "excluded",
    ],
)
def test_unproven_opening_conversion_does_not_grant_variant_stock(opening_db, case):
    db = opening_db
    legacy_opening(db)
    db.get(models.Product, 1).variant_mode = "inventory"
    excluded = None
    if case == "unlinked":
        db.query(models.WarehouseDocument).filter_by(
            source_type="opening_balance"
        ).one().source_document_id = None
        conversion(db)
    elif case in {"draft", "cancelled"}:
        conversion(db, status=case)
    elif case == "wrong_warehouse":
        conversion(db, warehouse=12)
    elif case == "partial":
        conversion(db, 9, ((1, 5), (2, 4)))
    elif case == "unallocated":
        conversion(db, splits=())
    elif case == "duplicate":
        conversion(db)
        conversion(db)
    elif case == "excluded":
        excluded = [conversion(db)]
    db.flush()

    with pytest.raises(ApiError) as exc:
        compute_available_variant_stock(
            db, 1, 1, 11, 1, DAY, exclude_warehouse_document_ids=excluded
        )
    assert (exc.value.code, exc.value.status_code) == ("LEGACY_OPENING_VARIANT_UNRESOLVED", 409)
