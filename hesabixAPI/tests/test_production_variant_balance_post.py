from decimal import Decimal

import pytest
from sqlalchemy import select

from adapters.db import models
from adapters.db.models.product_variant_allocation import WarehouseLineVariantAllocation
from app.services import variant_inventory_service as balances
from app.services.product_variant_service import list_variant_balances
from app.services.warehouse_service import create_manual_warehouse_document, post_warehouse_document
from tests.test_opening_variant_sync import opening_db as opening_db
from tests.test_warehouse_transfer_currency import DAY
from tests.test_warehouse_transfer_currency import transfer_db as transfer_db


@pytest.mark.parametrize("kind,quantities,expected", [
    ("production_in", (10, 12), {1: 10, 2: 12}),
    ("production_out", (2, 3), {1: 8, 2: 9}),
])
def test_production_post_flushes_status_and_rolls_back_with_balance(opening_db, monkeypatch, kind, quantities, expected):
    db = opening_db

    def create(doc_type, amounts):
        result = create_manual_warehouse_document(db, 1, 1, {
            "doc_type": doc_type, "document_date": DAY.isoformat(),
            "warehouse_id_from" if doc_type == "production_out" else "warehouse_id_to": 11,
            "lines": [{"product_id": 1, "quantity": qty, "allocations": [{"variant_id": vid, "quantity": qty}],
                       "extra_info": {"unit": "main", "cost_price": 100}} for vid, qty in zip((1, 2), amounts, strict=True)],
        })
        db.commit()
        return result.id

    def snapshot():
        return ([(r.id, r.status) for r in db.query(models.WarehouseDocument).order_by(models.WarehouseDocument.id)],
                list_variant_balances(db, 1, 1, 11),
                [(r.id, r.warehouse_document_line_id, r.variant_id, r.quantity) for r in db.query(WarehouseLineVariantAllocation)])

    if kind == "production_out":
        arrival = create("receipt", (10, 12))
        post_warehouse_document(db, arrival)
        db.commit()
    did = create(kind, quantities)
    before = snapshot()
    original = balances.rebuild_balances_for_warehouse_document

    def observe(post_db, document):
        assert document.status == "posted"
        with post_db.no_autoflush:
            assert post_db.scalar(select(models.WarehouseDocument.status).where(models.WarehouseDocument.id == did)) == "posted"
        original(post_db, document)

    monkeypatch.setattr(balances, "rebuild_balances_for_warehouse_document", observe)
    post_warehouse_document(db, did)
    assert {r["variant_id"]: Decimal(r["quantity"]) for r in list_variant_balances(db, 1, 1, 11)} == expected
    db.rollback()  # Caller failure after the real rebuild, before commit.
    db.expire_all()
    assert snapshot() == before
    post_warehouse_document(db, did)
    db.commit()
    db.expire_all()
    assert {r["variant_id"]: Decimal(r["quantity"]) for r in list_variant_balances(db, 1, 1, 11)} == expected
    committed = snapshot()
    post_warehouse_document(db, did)
    assert snapshot() == committed
