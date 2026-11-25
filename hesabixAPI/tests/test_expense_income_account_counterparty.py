from datetime import date
from decimal import Decimal
from types import SimpleNamespace

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.db import models
from adapters.db.models.business import BusinessField, BusinessType
from app.core import cache
from app.core.responses import ApiError
from app.services.expense_income_service import (
    create_expense_income,
    is_person_control_account,
    update_expense_income,
)

DAY = date(2026, 11, 15)


def test_is_person_control_account_markers():
    assert is_person_control_account(
        SimpleNamespace(name="جاری شرکا", code="20503", account_type="liability")
    )
    assert is_person_control_account(
        SimpleNamespace(name="حساب‌های پرداختنی", code="20201", account_type="person")
    )
    assert is_person_control_account(
        SimpleNamespace(name="Other", code="20503", account_type="liability")
    )
    assert not is_person_control_account(
        SimpleNamespace(name="محمد", code="2050301", account_type="liability")
    )
    assert not is_person_control_account(
        SimpleNamespace(name="هزینه اجاره", code="70401", account_type="expense")
    )


@pytest.fixture
def db(monkeypatch):
    monkeypatch.setattr(cache, "_redis_config", {"enabled": False})
    monkeypatch.setattr(cache, "_redis_config_expires_at", float("inf"))
    monkeypatch.setattr(cache, "_redis_client", None)
    monkeypatch.setattr(cache, "_cache_service", None)
    n = {"i": 0}

    def _next_code(*_a, **_k):
        n["i"] += 1
        return f"EXP-{n['i']}"

    monkeypatch.setattr(
        "app.services.expense_income_service.generate_document_code",
        _next_code,
    )
    monkeypatch.setattr(
        "app.services.expense_income_service.ensure_document_policy_allows_creation",
        lambda *_a, **_k: {"allowed": True},
    )

    engine = create_engine("sqlite://")
    tables = models.Base.metadata.tables
    names = (
        "users",
        "currencies",
        "businesses",
        "fiscal_years",
        "accounts",
        "persons",
        "documents",
        "document_lines",
    )
    with Session(engine, autoflush=False) as session:
        for name in names:
            session.execute(CreateTable(tables[name]))
        session.add_all(
            [
                models.User(
                    id=1,
                    email="t@example.com",
                    password_hash="x",
                    referral_code="r1",
                    is_active=True,
                ),
                models.Currency(id=1, name="Base", title="Base", symbol="B", code="IRR", decimal_places=0),
                models.Business(
                    id=1,
                    name="Test",
                    owner_id=1,
                    default_currency_id=1,
                    business_type=BusinessType.SHOP,
                    business_field=BusinessField.TRADING,
                ),
                models.FiscalYear(id=1, business_id=1, title="FY", start_date=DAY, end_date=DAY, is_last=True),
                models.Account(id=10, code="70401", name="هزینه اجاره", account_type="expense"),
                models.Account(id=20, code="20201", name="حساب‌های پرداختنی", account_type="person"),
                models.Account(id=30, code="20503", name="جاری شرکا", account_type="liability"),
                models.Account(
                    id=31,
                    code="2050301",
                    name="محمد",
                    account_type="liability",
                    parent_id=30,
                ),
                models.Person(id=7, business_id=1, alias_name="محمد", person_types='["سهامدار"]'),
            ]
        )
        session.commit()
        yield session
    engine.dispose()


def _payload(counterparty):
    return {
        "document_type": "expense",
        "document_date": DAY.isoformat(),
        "currency_id": 1,
        "item_lines": [{"account_id": 10, "amount": 1000}],
        "counterparty_lines": [counterparty],
    }


def _credit_line(db, document_id):
    return (
        db.query(models.DocumentLine)
        .filter(
            models.DocumentLine.document_id == document_id,
            models.DocumentLine.credit > 0,
        )
        .one()
    )


def test_account_tafsili_leaf_posts_selected_account_not_payable(db):
    created = create_expense_income(
        db,
        1,
        1,
        _payload(
            {
                "transaction_type": "account",
                "account_id": 31,
                "account_name": "2050301 - محمد",
                "amount": 1000,
            }
        ),
        skip_post_commit_hooks=True,
    )
    line = _credit_line(db, created["id"])
    assert line.account_id == 31
    assert line.person_id is None
    assert line.credit == Decimal("1000")
    assert line.extra_info["transaction_type"] == "account"


def test_account_type_without_account_id_is_rejected(db):
    with pytest.raises(ApiError) as ei:
        create_expense_income(
            db,
            1,
            1,
            _payload({"transaction_type": "account", "amount": 1000}),
            skip_post_commit_hooks=True,
        )
    assert ei.value.error_code == "ACCOUNT_REQUIRED"


def test_current_partners_parent_requires_person_tafsili(db):
    with pytest.raises(ApiError) as ei:
        create_expense_income(
            db,
            1,
            1,
            _payload(
                {
                    "transaction_type": "account",
                    "account_id": 30,
                    "account_name": "جاری شرکا",
                    "amount": 1000,
                }
            ),
            skip_post_commit_hooks=True,
        )
    assert ei.value.error_code == "PERSON_REQUIRED"


def test_current_partners_parent_posts_selected_account_with_person(db):
    created = create_expense_income(
        db,
        1,
        1,
        _payload(
            {
                "transaction_type": "account",
                "account_id": 30,
                "account_name": "جاری شرکا",
                "person_id": 7,
                "person_name": "محمد",
                "amount": 1000,
            }
        ),
        skip_post_commit_hooks=True,
    )
    line = _credit_line(db, created["id"])
    assert line.account_id == 30
    assert line.person_id == 7
    assert line.credit == Decimal("1000")
    assert line.extra_info["transaction_type"] == "account"
    assert line.extra_info["person_id"] == 7
    assert line.extra_info["person_name"] == "محمد"
    counterparties = [row for row in created["counterparties"]]
    assert counterparties[0]["account_code"] == "20503"
    assert counterparties[0]["person_id"] == 7


def test_person_type_still_uses_payable(db):
    created = create_expense_income(
        db,
        1,
        1,
        _payload(
            {
                "transaction_type": "person",
                "person_id": 7,
                "person_name": "محمد",
                "amount": 1000,
            }
        ),
        skip_post_commit_hooks=True,
    )
    line = _credit_line(db, created["id"])
    assert line.account_id == 20
    assert line.person_id == 7


def test_update_keeps_selected_partners_account(db):
    created = create_expense_income(
        db,
        1,
        1,
        _payload(
            {
                "transaction_type": "account",
                "account_id": 31,
                "amount": 1000,
            }
        ),
        skip_post_commit_hooks=True,
    )
    updated = update_expense_income(
        db,
        created["id"],
        1,
        {
            "document_date": DAY.isoformat(),
            "currency_id": 1,
            "item_lines": [{"account_id": 10, "amount": 1500}],
            "counterparty_lines": [
                {
                    "transaction_type": "account",
                    "account_id": 30,
                    "account_name": "جاری شرکا",
                    "person_id": 7,
                    "person_name": "محمد",
                    "amount": 1500,
                }
            ],
        },
    )
    line = _credit_line(db, updated["id"])
    assert line.account_id == 30
    assert line.person_id == 7
    assert line.credit == Decimal("1500")
