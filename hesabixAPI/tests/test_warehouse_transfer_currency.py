from datetime import date

import pytest
from sqlalchemy import BigInteger, Integer, MetaData, create_engine, select
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.db import models
from adapters.db.models.business import BusinessField, BusinessType
from adapters.db.models.document_monetization import DocumentUsagePolicy
from adapters.db.models.invoice_item_line import InvoiceItemLine
from app.core import business_calendar, cache
from app.core.responses import ApiError
from app.services import woocommerce_stock_push_hook
from app.services.warehouse_service import create_manual_warehouse_document, post_warehouse_document

DAY = date(2026, 11, 11)


@pytest.fixture
def transfer_db(monkeypatch):
    monkeypatch.setattr(cache, "get_redis_client", lambda *args, **kwargs: None)
    monkeypatch.setattr(cache, "_cache_service", None)
    monkeypatch.setattr(business_calendar, "business_today", lambda *args: DAY)
    monkeypatch.setattr(woocommerce_stock_push_hook, "_execute_stock_push", lambda *args: None)
    engine = create_engine("sqlite://")
    names = [
        "businesses", "currencies", "business_currencies", "fiscal_years", "products", "warehouses",
        "documents", "document_lines", "warehouse_documents", "warehouse_document_lines",
        "warehouse_line_variant_allocations", "warehouse_line_lot_allocations", "product_instances",
        "product_variants", "inventory_variant_balances", InvoiceItemLine.__table__.name,
        "invoice_item_line_variant_allocations", "document_usage_policies", "workflows",
        "warehouse_product_placements", "warehouse_locations", "business_document_numbering_settings",
        "document_code_reservations", "document_number_counters",
    ]
    with engine.begin() as connection:
        for name in names:
            table = models.Base.metadata.tables[name].to_metadata(MetaData())
            for column in table.primary_key:
                if isinstance(column.type, BigInteger):
                    column.type = Integer()  # SQLite autoincrement requires the literal INTEGER type.
            connection.execute(CreateTable(table, include_foreign_key_constraints=[]))
    with Session(engine, autoflush=False, expire_on_commit=False) as db:
        db.add_all([models.Currency(id=idx, name=code, title=code, symbol=code, code=code)
                    for idx, code in ((1, "IRR"), (2, "USD"), (3, "EUR"))])
        for bid, cid in ((1, 2), (2, 3), (3, None)):
            db.add_all([
                models.Business(id=bid, name=str(bid), owner_id=1, default_currency_id=cid,
                                business_type=BusinessType.SHOP, business_field=BusinessField.TRADING),
                models.FiscalYear(id=bid, business_id=bid, title="FY", start_date=DAY, end_date=DAY, is_last=True),
                models.Product(id=bid, business_id=bid, code="P", name="P", main_unit="each",
                               inventory_mode="bulk", variant_mode="none", track_inventory=False),
                models.Warehouse(id=bid * 10 + 1, business_id=bid, name="From", code="FROM"),
                models.Warehouse(id=bid * 10 + 2, business_id=bid, name="To", code="TO"),
                DocumentUsagePolicy(business_id=bid, policy_type="free", title="Test", is_active=True),
            ])
        db.commit()
        yield db
    engine.dispose()


def draft_transfer(db, bid):
    doc = create_manual_warehouse_document(db, bid, 1, {
        "doc_type": "transfer", "document_date": DAY.isoformat(),
        "warehouse_id_from": bid * 10 + 1, "warehouse_id_to": bid * 10 + 2,
        "lines": [{"product_id": bid, "quantity": 2, "extra_info": {"unit": "main"}}],
    })
    db.commit()
    return doc


@pytest.mark.parametrize("bid,expected_currency", [(1, 2), (2, 3)])
def test_transfer_ledger_uses_business_base_currency(transfer_db, bid, expected_currency):
    db = transfer_db
    doc = draft_transfer(db, bid)
    post_warehouse_document(db, doc.id)
    db.commit()
    db.expire_all()
    ledger = db.scalars(select(models.Document).where(models.Document.business_id == bid)).one()
    assert ledger.currency_id == expected_currency
    assert ledger.document_type == "inventory_transfer" and doc.status == "posted"
    assert [(r.quantity, r.debit, r.credit) for r in db.query(models.DocumentLine).all()] == [(2, 0, 0)] * 2


@pytest.mark.parametrize("currency_id,code,status", [(None, "BUSINESS_CURRENCY", 400), (999, "CURRENCY_NOT_FOUND", 404)])
def test_transfer_without_valid_base_currency_has_no_posting_effects(transfer_db, currency_id, code, status):
    db = transfer_db
    db.get(models.Business, 3).default_currency_id = currency_id
    db.commit()
    doc = draft_transfer(db, 3)
    with pytest.raises(ApiError) as error:
        post_warehouse_document(db, doc.id)
    assert (error.value.code, error.value.status_code) == (code, status)
    db.rollback()
    db.expire_all()
    assert doc.status == "draft"
    assert db.query(models.Document).count() == db.query(models.DocumentLine).count() == 0
    assert db.query(models.Base.metadata.tables["inventory_variant_balances"]).count() == 0
