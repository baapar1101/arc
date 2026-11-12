from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.db import models
from adapters.db.models.business import BusinessField, BusinessType
from adapters.db.models.cash_register import CashRegister
from adapters.db.models.document_monetization import DocumentUsagePolicy
from adapters.db.models.document_numbering import BusinessDocumentNumberingSetting, DocumentNumberCounter
from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin
from app.core import cache
from app.services.invoice_service import (
    batch_calculate_invoices_remaining,
    calculate_invoice_remaining,
    create_invoice,
)
from app.services.receipt_payment_service import create_receipt_payment

DAY = date(2026, 11, 11)
ACCOUNTS = (
    "10401", "10405", "10102", "10104", "10106", "10107", "10202",
    "20101", "40001", "40003", "50001", "50002", "50003",
    "60205", "70401", "70406", "70407", "70408",
)


@pytest.fixture
def db(monkeypatch):
    monkeypatch.setattr(cache, "_redis_config", {"enabled": False})
    monkeypatch.setattr(cache, "_redis_config_expires_at", float("inf"))
    monkeypatch.setattr(cache, "_redis_client", None)
    monkeypatch.setattr(cache, "_cache_service", None)
    engine = create_engine("sqlite://")
    tables = models.Base.metadata.tables
    names = (
        "businesses", "currencies", "fiscal_years", "products", "documents", "document_lines",
        "invoice_item_lines", "document_usage_policies", "invoice_item_line_variant_allocations",
        "invoice_item_line_lot_allocations", "users", "accounts", "persons", "fa_assets",
        "cash_registers", "business_currencies",
        "document_invoice_tags", "warehouse_documents", "wallet_transactions",
    )
    with Session(engine, autoflush=False) as session:
        for table in [*(tables[name] for name in names), BusinessDocumentNumberingSetting.__table__,
                      DocumentNumberCounter.__table__, BusinessPlugin.__table__, MarketplacePlugin.__table__]:
            session.execute(CreateTable(table))
        session.add_all([
            models.Business(id=1, name="Test", owner_id=1, default_currency_id=1,
                            business_type=BusinessType.SHOP, business_field=BusinessField.TRADING),
            models.FiscalYear(id=1, business_id=1, title="Test", start_date=DAY, end_date=DAY, is_last=True),
            models.Currency(id=1, name="Base", title="Base", symbol="B", code="B", decimal_places=2),
            models.Currency(id=2, name="Other", title="Other", symbol="O", code="O", decimal_places=2),
            models.Product(id=1, business_id=1, code="P", name="P", track_inventory=False),
            models.Person(id=1, business_id=1, alias_name="Buyer", person_types="[]"),
            DocumentUsagePolicy(business_id=1, policy_type="free", title="Test", is_active=True),
            CashRegister(id=1, business_id=1, currency_id=1, name="Cash"),
            *(models.Account(code=code, name=code, account_type="system") for code in ACCOUNTS),
        ])
        session.commit()
        yield session
    engine.dispose()


def _sale(db, code):
    result = create_invoice(db, 1, 1, {
        "invoice_type": "invoice_sales", "document_date": DAY.isoformat(), "currency_id": 1,
        "code": code, "extra_info": {"person_id": 1, "post_inventory": False},
        "lines": [{"product_id": 1, "quantity": 1, "extra_info": {
            "unit_price": 500, "tax_rate": 10, "tax_amount": 50, "line_total": 550,
        }}],
    }, commit=False)
    db.commit()
    return db.get(models.Document, result["data"]["id"])


def _receipt(db, *allocations, extra=None):
    result = create_receipt_payment(db, 1, 1, {
        "document_type": "receipt", "document_date": DAY.isoformat(), "currency_id": 1,
        "person_lines": [{"person_id": 1, "amount": amount, "extra_info": {"invoice_id": invoice_id}}
                         for invoice_id, amount in allocations],
        "account_lines": [{"transaction_type": "cash_register", "cash_register_id": 1,
                           "amount": sum(amount for _, amount in allocations)}],
        "extra_info": extra or {},
    })
    db.expire_all()
    return db.get(models.Document, result["id"])


def _assert_balances(db, invoices, expected):
    single = [calculate_invoice_remaining(db, 1, invoice.id) for invoice in invoices]
    batch = batch_calculate_invoices_remaining(db, 1, invoices)
    observed = [(row["paid_amount"], row["remaining"]) for row in single]
    print(f"single={observed} batch={batch}")
    assert [batch[invoice.id] for invoice in invoices] == single
    assert observed == expected


def test_shared_receipt_uses_each_stored_receivable_allocation_once(db):
    a, b = _sale(db, "SALE-A"), _sale(db, "SALE-B")
    receipt = _receipt(db, (a.id, 100), (b.id, 150))
    assert receipt.currency_id == a.currency_id == b.currency_id == 1
    assert all(invoice.extra_info["links"]["receipt_payment_document_ids"] == [receipt.id] for invoice in (a, b))
    assert [(line.extra_info["invoice_id"], line.person_id, line.debit, line.credit)
            for line in receipt.lines if line.account.code == "10401"] == [
        (a.id, 1, 0, 100), (b.id, 1, 0, 150),
    ]
    assert [line.debit for line in receipt.lines if line.account.code == "10202"] == [Decimal(250)]
    assert all(sum(line.debit for line in invoice.lines if line.account.code == "10401") == 550
               for invoice in (a, b))
    _assert_balances(db, (a, b), [(100, 450), (150, 400)])

    # A duplicated header link and the matching person line still identify a single receipt.
    extra = dict(a.extra_info)
    extra["links"] = {**extra["links"], "receipt_payment_document_ids": [receipt.id, receipt.id]}
    a.extra_info = extra
    db.commit()
    _receipt(db, (a.id, 25))
    _assert_balances(db, (a, b), [(125, 425), (150, 400)])


@pytest.mark.parametrize("mode", ["legacy", "fx"])
def test_single_invoice_receipt_preserves_existing_fallback(db, mode):
    invoice = _sale(db, "SALE")
    if mode == "legacy":
        _receipt(db, (None, 100), extra={"invoice_id": invoice.id})
        _assert_balances(db, (invoice,), [(100, 450)])
    else:
        # Reproduce the persisted FX shape: GL amounts are in base, while the
        # receipt-level settlement amount belongs to the invoice's currency.
        invoice.currency_id = 2
        db.commit()
        _receipt(db, (invoice.id, 25), extra={
            "invoice_id": invoice.id, "cross_currency": True, "settles_currency_id": 2,
            "fx_settlement": {"settles_amount": "250", "settles_currency_id": 2},
        })
        _assert_balances(db, (invoice,), [(250, 300)])
