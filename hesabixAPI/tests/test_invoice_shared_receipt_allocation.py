from datetime import UTC, date
from decimal import Decimal

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.db import models
from adapters.db.models.business import BusinessField, BusinessType
from adapters.db.models.cash_register import CashRegister
from adapters.db.models.document_monetization import DocumentUsagePolicy
from adapters.db.models.document_numbering import (
    BusinessDocumentNumberingSetting,
    DocumentNumberCounter,
)
from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin
from app.core import cache
from app.core.responses import ApiError
from app.services.invoice_service import (
    batch_calculate_invoices_remaining,
    calculate_invoice_remaining,
    create_invoice,
)
from app.services.receipt_invoice_allocation_service import ALLOCATION_KEY, CONTRACT_KEY
from app.services.receipt_payment_service import (
    create_receipt_payment,
    get_receipt_payment,
    update_receipt_payment,
)

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


def _sale(db, code, currency_id=1):
    result = create_invoice(db, 1, 1, {
        "invoice_type": "invoice_sales", "document_date": DAY.isoformat(), "currency_id": currency_id,
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


@pytest.fixture
def fx_db(db):
    from datetime import datetime

    from adapters.db.models.business_currency_rate import BusinessCurrencyRate
    from adapters.db.models.currency import BusinessCurrency

    db.execute(CreateTable(BusinessCurrencyRate.__table__))
    now = datetime(2026, 1, 1, tzinfo=UTC)
    db.add(BusinessCurrency(business_id=1, currency_id=2))
    db.add(BusinessCurrencyRate(business_id=1, currency_id=2, rate=Decimal("0.1"),
                               effective_at=now, created_by_user_id=1, created_at=now, updated_at=now))
    db.get(models.Currency, 1).round_monetary_amounts = True
    db.commit()
    return db


def _fx_payload(invoices, shares):
    return {
        "document_type": "receipt", "document_date": DAY.isoformat(), "currency_id": 2,
        "person_lines": [{"person_id": 1, "amount": str(amount), "extra_info": {"invoice_id": invoice.id}}
                         for invoice, amount in zip(invoices, shares, strict=True)],
        "account_lines": [{"transaction_type": "cash_register", "cash_register_id": 1,
                           "amount": 25, "settles_amount": 250, "invoice_rate_to_base": "0.1"}],
    }


@pytest.mark.parametrize("shares,expected", [
    (["100", "150"], [(100, 450), (150, 400)]),
    (["100.01", "149.99"], [(100.01, 449.99), (149.99, 400.01)]),
    (["0.01", "249.99"], [(0.01, 549.99), (249.99, 300.01)]),
])
def test_fx_receipt_retains_exact_invoice_currency_before_base_rounding(fx_db, shares, expected):
    db = fx_db
    invoices = [_sale(db, "FX-A", 2), _sale(db, "FX-B", 2)]
    result = create_receipt_payment(db, 1, 1, _fx_payload(invoices, shares))
    db.expire_all()
    receipt = db.get(models.Document, result["id"])
    assert receipt.currency_id == 1
    assert [str(line.credit) for line in receipt.lines if line.person_id] == [
        str((Decimal(amount) / 10).quantize(Decimal(".01"))) for amount in shares]
    assert sum(line.debit for line in receipt.lines) == sum(line.credit for line in receipt.lines) == 25
    readback = get_receipt_payment(db, receipt.id)
    assert [line["extra_info"][ALLOCATION_KEY]["amount"] for line in readback["person_lines"]] == shares
    _assert_balances(db, invoices, expected)


def test_fx_update_replaces_shares_and_removed_allocation_does_not_fall_back_to_header(fx_db):
    db = fx_db
    invoices = [_sale(db, "EDIT-A", 2), _sale(db, "EDIT-B", 2)]
    rid = create_receipt_payment(db, 1, 1, _fx_payload(invoices, [100, 150]))["id"]
    update_receipt_payment(db, rid, 1, _fx_payload(invoices, ["100.01", "149.99"]))
    db.expire_all()
    _assert_balances(db, invoices, [(100.01, 449.99), (149.99, 400.01)])
    body = _fx_payload(invoices[1:], [250])
    body["extra_info"] = {"invoice_id": invoices[0].id}
    update_receipt_payment(db, rid, 1, body)
    db.expire_all()
    _assert_balances(db, invoices, [(0, 550), (250, 300)])
    create_receipt_payment(db, 1, 1, _fx_payload(invoices[1:], [250]))
    db.expire_all()
    _assert_balances(db, invoices, [(0, 550), (500, 50)])


def test_fx_readback_update_uses_stored_identity_and_ignores_forged_metadata(fx_db):
    db = fx_db
    invoices = [_sale(db, "READ-A", 2), _sale(db, "READ-B", 2)]
    body = _fx_payload(invoices, ["100.01", "149.99"])
    body["developer_settings"] = {CONTRACT_KEY: 999}
    for line in body["person_lines"]:
        line["developer_data"] = {ALLOCATION_KEY: {"amount": "9999"}}
        line["extra_info"][ALLOCATION_KEY] = {"amount": "9999"}
    rid = create_receipt_payment(db, 1, 1, body)["id"]
    readback = get_receipt_payment(db, rid)
    readback["developer_settings"] = {CONTRACT_KEY: 999}
    for line in readback["person_lines"]:
        line["extra_info"][ALLOCATION_KEY]["amount"] = "9999"
    update_receipt_payment(db, rid, 1, readback)
    db.expire_all()
    _assert_balances(db, invoices, [(100.01, 449.99), (149.99, 400.01)])


@pytest.mark.parametrize("invalid", ["currency", "person", "business", "missing", "nan"])
def test_invalid_fx_invoice_allocation_is_rejected_before_writing(fx_db, invalid):
    db = fx_db
    invoice = _sale(db, "INVALID", 2)
    body = _fx_payload([invoice], [250])
    if invalid in ("currency", "business"):
        setattr(invoice, "currency_id" if invalid == "currency" else "business_id", 1 if invalid == "currency" else 2)
        db.commit()
    elif invalid == "person":
        body["person_lines"][0]["person_id"] = 2
    elif invalid == "missing":
        body["person_lines"][0]["extra_info"]["invoice_id"] = 999999
    else:
        body["person_lines"][0]["amount"] = "NaN"
    before = db.query(models.Document).count()
    with pytest.raises(ApiError):
        create_receipt_payment(db, 1, 1, body)
    db.rollback()
    assert db.query(models.Document).count() == before


def test_fx_receipt_rollback_discards_allocation_and_financial_lines(fx_db):
    db = fx_db
    invoices = [_sale(db, "ROLL-A", 2), _sale(db, "ROLL-B", 2)]
    before = (db.query(models.Document).count(), db.query(models.DocumentLine).count())
    result = create_receipt_payment(db, 1, 1, _fx_payload(invoices, [100, 150]), commit=False)
    assert db.get(models.Document, result["id"]).developer_settings[CONTRACT_KEY] == 1
    db.rollback()
    assert (db.query(models.Document).count(), db.query(models.DocumentLine).count()) == before
    _assert_balances(db, invoices, [(0, 550), (0, 550)])


def test_fx_two_distinct_allocations_to_same_invoice_are_both_counted(fx_db):
    db = fx_db
    invoice = _sale(db, "TWO-LINES", 2)
    body = _fx_payload([invoice, invoice], [100, 150])
    create_receipt_payment(db, 1, 1, body)
    db.expire_all()
    _assert_balances(db, [invoice], [(250, 300)])


def test_fx_readback_with_changed_rounded_amount_is_rejected_without_writing(fx_db):
    db = fx_db
    invoices = [_sale(db, "REJECT-A", 2), _sale(db, "REJECT-B", 2)]
    rid = create_receipt_payment(db, 1, 1, _fx_payload(invoices, ["100.01", "149.99"]))["id"]
    body = get_receipt_payment(db, rid)
    body["person_lines"][0]["amount"] = 11
    before = [(line.id, line.debit, line.credit) for line in db.get(models.Document, rid).lines]
    with pytest.raises(ApiError, match="INVOICE_ALLOCATION_CURRENCY_REQUIRED"):
        update_receipt_payment(db, rid, 1, body)
    db.rollback()
    assert [(line.id, line.debit, line.credit) for line in db.get(models.Document, rid).lines] == before
    _assert_balances(db, invoices, [(100.01, 449.99), (149.99, 400.01)])
