from decimal import Decimal

import pytest
from sqlalchemy import event
from sqlalchemy.schema import CreateTable

from adapters.db import models
from adapters.db.models.activity_log import ActivityLog
from adapters.db.models.product_variant import ProductVariant
from adapters.db.models.product_variant_allocation import WarehouseLineVariantAllocation
from app.core.responses import ApiError
from app.services.opening_balance_service import (
    post_opening_balance,
    unpost_opening_balance,
    upsert_opening_balance,
)
from app.services.opening_balance_warehouse_sync_service import (
    sync_opening_balance_warehouse_documents as synchronize,
)
from app.services.product_variant_service import list_variant_balances
from tests.test_warehouse_transfer_currency import DAY as DAY
from tests.test_warehouse_transfer_currency import transfer_db as transfer_db


@pytest.fixture
def opening_db(transfer_db):
    db = transfer_db
    event.listen(db.bind, "begin", lambda connection: connection.exec_driver_sql("BEGIN"))
    with db.bind.begin() as connection:
        for model in (models.Account, models.User, ActivityLog):
            connection.execute(CreateTable(model.__table__, include_foreign_key_constraints=[]))
    product = db.get(models.Product, 1)
    product.variant_mode, product.track_inventory = "inventory", True
    product.main_unit, product.secondary_unit, product.unit_conversion_factor = "carton", "each", Decimal(10)
    db.add_all([
        models.User(id=1, first_name="Test", password_hash="fixture", referral_code="OPENINGSYNC"),
        models.Account(id=1, business_id=1, code="INV", name="Inventory", account_type="asset"),
        models.Account(id=2, business_id=1, code="EQUITY", name="Equity", account_type="equity"),
        models.Product(id=4, business_id=1, code="OTHER", name="Other", variant_mode="inventory"),
    ])
    for vid, bid, pid in ((1, 1, 1), (2, 1, 1), (3, 2, 2), (4, 1, 4)):
        db.add(ProductVariant(id=vid, business_id=bid, product_id=pid, combination_key=str(vid)))
    db.commit()
    return db


def payload(shares=(8, 12), unit="main", cost=None):
    scale = 10 if unit == "each" else 1
    return {
        "fiscal_year_id": 1, "currency_id": 2, "inventory_account_id": 1, "equity_account_id": 2,
        "auto_balance_to_equity": True,
        "inventory_lines": [{"product_id": 1, "quantity": sum(shares) * scale,
                             "allocations": [{"variant_id": vid, "quantity": qty * scale} for vid, qty in zip((1, 2), shares, strict=True)],
                             "extra_info": {"warehouse_id": 11, "unit": unit,
                                            "cost_price": (10 if scale == 10 else 100) if cost is None else cost}}],
    }


def save(db, data):
    result = upsert_opening_balance(db, 1, 1, data, auto_commit=False, return_details=False)
    db.commit()
    return result["id"]


def gl(db):
    return [(r.id, r.quantity, r.debit, r.credit, r.extra_info) for r in db.query(models.DocumentLine).order_by(models.DocumentLine.id)]


def physical(db):
    return {r["variant_id"]: Decimal(r["quantity"]) for r in list_variant_balances(db, 1, 1, 11)}


@pytest.mark.parametrize("unit", ["main", "each"])
def test_sync_and_legal_share_edit_preserve_variant_main_quantities(opening_db, unit):
    db = opening_db
    did = save(db, payload(unit=unit))
    before_gl = gl(db)
    first = synchronize(db, 1, 1, did, [1])
    db.commit()
    assert first["receipts_created"] == 1 and physical(db) == {1: 8, 2: 12}
    assert gl(db) == before_gl
    assert sorted((r.variant_id, r.quantity) for r in db.query(WarehouseLineVariantAllocation)) == [(1, 8), (2, 12)]
    assert all(r.extra_info["cost_price"] == 100 for r in db.query(models.WarehouseDocumentLine))
    again = synchronize(db, 1, 1, did, [1])
    db.commit()
    assert again["document_ids"] == [] and db.query(models.WarehouseDocument).count() == 1
    post_opening_balance(db, 1, 1, 1)
    with pytest.raises(ApiError) as error:
        upsert_opening_balance(db, 1, 1, payload((7, 13), unit), auto_commit=False)
    assert error.value.code == "OPENING_BALANCE_POSTED"
    unpost_opening_balance(db, 1, 1, 1)
    save(db, payload((7, 13), unit))
    edited = synchronize(db, 1, 1, did, [1])
    db.commit()
    assert (edited["issues_created"], edited["receipts_created"]) == (1, 1)
    assert physical(db) == {1: 7, 2: 13}
    assert sum(r.debit for r in db.query(models.DocumentLine)) == 2000
    assert sum(r.credit for r in db.query(models.DocumentLine)) == 2000
    assert synchronize(db, 1, 1, did, [1])["document_ids"] == []


@pytest.mark.parametrize("vid,qty,code", [(999, 20, "VARIANT_NOT_FOUND"), (3, 20, "VARIANT_NOT_FOUND"),
                                         (4, 20, "VARIANT_NOT_FOUND"), (1, 19, "VARIANT_ALLOCATION_MISMATCH"),
                                         (None, 0, "VARIANT_REQUIRED")])
def test_opening_financial_write_rejects_invalid_explicit_allocation(opening_db, vid, qty, code):
    db = opening_db
    data = payload()
    data["inventory_lines"][0]["allocations"] = [{"variant_id": vid, "quantity": qty}] if vid else []
    with pytest.raises(ApiError) as error:
        upsert_opening_balance(db, 1, 1, data, auto_commit=False)
    assert error.value.code == code
    db.rollback()
    assert db.query(models.Document).count() == db.query(models.WarehouseDocument).count() == 0


def test_sync_rollback_restores_allocations_balances_and_allows_retry(opening_db):
    db = opening_db
    did = save(db, payload())
    before_gl = gl(db)
    synchronize(db, 1, 1, did, [1])
    assert physical(db) == {1: 8, 2: 12}
    db.rollback()
    assert db.query(models.WarehouseDocument).count() == db.query(WarehouseLineVariantAllocation).count() == 0
    assert physical(db) == {} and gl(db) == before_gl
    synchronize(db, 1, 1, did, [1])
    db.commit()
    assert physical(db) == {1: 8, 2: 12}


def test_changed_stock_cost_is_rejected_without_choosing_current_or_last_cost(opening_db):
    db = opening_db
    did = save(db, payload())
    synchronize(db, 1, 1, did, [1])
    db.commit()
    before_gl = gl(db)
    upsert_opening_balance(db, 1, 1, payload(cost=200), auto_commit=False)
    with pytest.raises(ApiError) as error:
        synchronize(db, 1, 1, did, [1])
    assert (error.value.code, error.value.status_code) == ("OPENING_VARIANT_COST_AMBIGUOUS", 409)
    db.rollback()
    assert physical(db) == {1: 8, 2: 12} and gl(db) == before_gl
