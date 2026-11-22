"""Opening-balance finalization belongs to the caller transaction.

Adapted from upstream to the current fork's accounting schema. Product-variant
inventory is intentionally not a prerequisite for finalization safety.
"""

from datetime import date

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.db import models
from adapters.db.models.activity_log import ActivityLog
from adapters.db.models.business import BusinessField, BusinessType
from app.core.responses import ApiError
from app.services.opening_balance_service import post_opening_balance, unpost_opening_balance

DAY = date(2026, 11, 11)


@pytest.fixture
def opening_db():
    engine = create_engine("sqlite://")
    tables = (models.Business, models.Currency, models.FiscalYear, models.User, models.Account,
              models.Document, models.DocumentLine, ActivityLog)
    with engine.begin() as connection:
        for model in tables:
            connection.execute(CreateTable(model.__table__, include_foreign_key_constraints=[]))
    with Session(engine, autoflush=False, expire_on_commit=False) as db:
        db.add_all([
            models.Business(id=1, name="Test", owner_id=1, default_currency_id=1,
                            business_type=BusinessType.SHOP, business_field=BusinessField.TRADING),
            models.Currency(id=1, name="Rial", title="Rial", code="IRR", symbol="IRR"),
            models.FiscalYear(id=1, business_id=1, title="FY", start_date=DAY, end_date=DAY, is_last=True),
            models.User(id=1, first_name="Test", last_name="Owner", password_hash="fixture", referral_code="OBTX"),
            models.Account(id=1, business_id=1, code="INV", name="Inventory", account_type="asset"),
            models.Account(id=2, business_id=1, code="EQUITY", name="Equity", account_type="equity"),
            models.Document(id=1, business_id=1, fiscal_year_id=1, currency_id=1, created_by_user_id=1,
                            code="OPENING", document_type="opening_balance", document_date=DAY,
                            is_proforma=False, extra_info={"posted": False}),
            models.DocumentLine(document_id=1, account_id=1, debit=1000, credit=0),
            models.DocumentLine(document_id=1, account_id=2, debit=0, credit=1000),
        ])
        db.commit()
        yield db
    engine.dispose()


def lines(db):
    return [(row.id, row.document_id, row.quantity, row.debit, row.credit, row.extra_info)
            for row in db.query(models.DocumentLine).order_by(models.DocumentLine.id)]


@pytest.mark.parametrize("initial,operation", [(False, post_opening_balance), (True, unpost_opening_balance)])
def test_caller_failure_rolls_back_finalization_and_activity(opening_db, initial, operation):
    db = opening_db
    db.get(models.Document, 1).extra_info = {"posted": initial}
    db.commit()
    before = lines(db)
    try:
        operation(db, 1, 1, 1)
        assert db.get(models.Document, 1).extra_info["posted"] is not initial
        raise RuntimeError("late caller failure")
    except RuntimeError:
        db.rollback()
    with Session(db.bind) as fresh:
        assert fresh.get(models.Document, 1).extra_info["posted"] is initial
        assert lines(fresh) == before
        assert fresh.query(ActivityLog).count() == 0


@pytest.mark.parametrize("initial,operation", [(False, post_opening_balance), (True, unpost_opening_balance)])
def test_root_commit_persists_and_repeated_operation_is_idempotent(opening_db, initial, operation):
    db = opening_db
    db.get(models.Document, 1).extra_info = {"posted": initial}
    db.commit()
    before = lines(db)
    for _ in range(2):
        operation(db, 1, 1, 1)
        db.commit()
    with Session(db.bind) as fresh:
        assert fresh.get(models.Document, 1).extra_info["posted"] is not initial
        assert lines(fresh) == before
        assert fresh.query(ActivityLog).count() == (1 if initial else 0)


def test_same_year_financial_guard_still_rejects_unpost_without_changes(opening_db):
    db = opening_db
    db.get(models.Document, 1).extra_info = {"posted": True}
    db.add(models.Document(id=2, business_id=1, fiscal_year_id=1, currency_id=1, created_by_user_id=1,
                           code="OTHER", document_type="accounting_document", document_date=DAY, is_proforma=False))
    db.add_all([models.DocumentLine(document_id=2, account_id=1, debit=20, credit=0),
                models.DocumentLine(document_id=2, account_id=2, debit=0, credit=20)])
    db.commit()
    before = lines(db)
    with pytest.raises(ApiError) as error:
        unpost_opening_balance(db, 1, 1, 1)
    assert (error.value.code, error.value.status_code) == ("OPENING_BALANCE_UNPOST_BLOCKED", 409)
    db.rollback()
    with Session(db.bind) as fresh:
        assert fresh.get(models.Document, 1).extra_info["posted"] is True
        assert lines(fresh) == before
