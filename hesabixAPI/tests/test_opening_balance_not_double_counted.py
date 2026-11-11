"""سند افتتاحیه نباید هم در مانده افتتاحیه و هم در گردش دوره جمع شود."""
from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from adapters.db import models
from adapters.db.models.business import BusinessField, BusinessType
from app.services.account_balance_core import compute_leaf_balances
from app.services.account_review_service import get_accounts_review_report
from app.services.general_ledger_service import get_general_ledger_report
from app.services.trial_balance_service import get_trial_balance_report

FY_START = date(2026, 3, 21)
FY_END = date(2027, 3, 20)
CAPITAL_OPENING = Decimal("7000000")
BANK_OPENING = Decimal("7000000")
PERIOD_RECEIPT = Decimal("100000")


@pytest.fixture
def db():
    engine = create_engine("sqlite://")
    tables = (
        "businesses",
        "currencies",
        "fiscal_years",
        "accounts",
        "documents",
        "document_lines",
    )
    models.Base.metadata.create_all(
        engine, tables=[models.Base.metadata.tables[name] for name in tables]
    )
    with Session(engine, autoflush=False) as session:
        session.add_all(
            [
                models.Business(
                    id=1,
                    name="Test",
                    business_type=BusinessType.SHOP,
                    business_field=BusinessField.TRADING,
                    owner_id=1,
                    default_currency_id=1,
                ),
                models.Currency(id=1, name="Rial", title="Rial", symbol="IRR", code="IRR"),
                models.FiscalYear(
                    id=1,
                    business_id=1,
                    title="1405",
                    is_last=True,
                    start_date=FY_START,
                    end_date=FY_END,
                ),
                models.Account(
                    id=10,
                    business_id=1,
                    code="10201",
                    name="بانک",
                    account_type="bank",
                ),
                models.Account(
                    id=20,
                    business_id=1,
                    code="30101",
                    name="سرمایه سهامدار یک",
                    account_type="accounting_document",
                ),
                models.Document(
                    id=1,
                    code="OPENING_BALANCE-260001",
                    business_id=1,
                    fiscal_year_id=1,
                    currency_id=1,
                    created_by_user_id=1,
                    document_date=FY_START,
                    document_type="opening_balance",
                    description="سند افتتاحیه",
                ),
                models.DocumentLine(
                    document_id=1,
                    account_id=10,
                    debit=BANK_OPENING,
                    credit=Decimal("0"),
                    debit_base=BANK_OPENING,
                    credit_base=Decimal("0"),
                ),
                models.DocumentLine(
                    document_id=1,
                    account_id=20,
                    debit=Decimal("0"),
                    credit=CAPITAL_OPENING,
                    debit_base=Decimal("0"),
                    credit_base=CAPITAL_OPENING,
                ),
                models.Document(
                    id=2,
                    code="REC-1",
                    business_id=1,
                    fiscal_year_id=1,
                    currency_id=1,
                    created_by_user_id=1,
                    document_date=date(2026, 6, 1),
                    document_type="receipt",
                    description="دریافت دوره",
                ),
                models.DocumentLine(
                    document_id=2,
                    account_id=10,
                    debit=PERIOD_RECEIPT,
                    credit=Decimal("0"),
                    debit_base=PERIOD_RECEIPT,
                    credit_base=Decimal("0"),
                ),
                models.DocumentLine(
                    document_id=2,
                    account_id=20,
                    debit=Decimal("0"),
                    credit=PERIOD_RECEIPT,
                    debit_base=Decimal("0"),
                    credit_base=PERIOD_RECEIPT,
                ),
            ]
        )
        session.flush()
        yield session
    engine.dispose()


def test_opening_only_day_does_not_repeat_opening_in_period(db):
    """سناریوی گزارش‌شده: فقط سند افتتاحیه در بازه؛ گردش دوره باید صفر باشد."""
    balances = compute_leaf_balances(db, 1, [10, 20], FY_START, FY_START, 1)
    bank = balances[10]
    capital = balances[20]
    assert bank.opening_debit == BANK_OPENING
    assert bank.period_debit == Decimal("0")
    assert bank.closing_debit == BANK_OPENING
    assert capital.opening_credit == CAPITAL_OPENING
    assert capital.period_credit == Decimal("0")
    assert capital.closing_credit == CAPITAL_OPENING


def test_leaf_balances_count_opening_document_only_once(db):
    balances = compute_leaf_balances(
        db, 1, [10, 20], FY_START, FY_END, 1
    )
    bank = balances[10]
    capital = balances[20]

    assert bank.opening_debit == BANK_OPENING
    assert bank.opening_credit == Decimal("0")
    assert bank.period_debit == PERIOD_RECEIPT
    assert bank.period_credit == Decimal("0")
    assert bank.closing_debit == BANK_OPENING + PERIOD_RECEIPT
    assert bank.closing_net == BANK_OPENING + PERIOD_RECEIPT

    assert capital.opening_credit == CAPITAL_OPENING
    assert capital.opening_debit == Decimal("0")
    assert capital.period_credit == PERIOD_RECEIPT
    assert capital.period_debit == Decimal("0")
    assert capital.closing_credit == CAPITAL_OPENING + PERIOD_RECEIPT
    assert capital.closing_net == -(CAPITAL_OPENING + PERIOD_RECEIPT)


def test_mid_year_range_does_not_double_opening_in_opening_column(db):
    """اگر بازه از وسط سال شروع شود، سند افتتاحیه نباید دوباره در مانده افتتاحیه بیاید."""
    date_from = date(2026, 8, 1)
    balances = compute_leaf_balances(db, 1, [20], date_from, FY_END, 1)
    capital = balances[20]
    assert capital.opening_credit == CAPITAL_OPENING + PERIOD_RECEIPT
    assert capital.period_credit == Decimal("0")
    assert capital.closing_credit == CAPITAL_OPENING + PERIOD_RECEIPT


def test_trial_balance_closing_is_not_doubled(db):
    report = get_trial_balance_report(
        db,
        business_id=1,
        fiscal_year_id=1,
        date_from=FY_START.isoformat(),
        date_to=FY_END.isoformat(),
        include_zero_balance=True,
        skip=0,
        take=50,
    )
    by_id = {item["account_id"]: item for item in report["items"]}
    capital = by_id[20]
    assert capital["opening_credit"] == float(CAPITAL_OPENING)
    assert capital["period_credit"] == float(PERIOD_RECEIPT)
    assert capital["closing_credit"] == float(CAPITAL_OPENING + PERIOD_RECEIPT)
    assert capital["closing_credit"] != float(CAPITAL_OPENING * 2)


def test_general_ledger_excludes_opening_document_from_period(db):
    report = get_general_ledger_report(
        db,
        business_id=1,
        account_ids=[20],
        fiscal_year_id=1,
        date_from=FY_START.isoformat(),
        date_to=FY_END.isoformat(),
        skip=0,
        take=50,
    )
    summary = report["summary"]
    assert summary["opening_balance"] == float(-CAPITAL_OPENING)
    assert summary["total_credit"] == float(PERIOD_RECEIPT)
    assert summary["total_debit"] == 0.0
    assert summary["closing_balance"] == float(-(CAPITAL_OPENING + PERIOD_RECEIPT))
    assert all(item["document_type"] != "opening_balance" for item in report["items"])
    assert [item["document_code"] for item in report["items"]] == ["REC-1"]


def test_account_review_details_do_not_replay_opening_document(db):
    report = get_accounts_review_report(
        db,
        business_id=1,
        fiscal_year_id=1,
        date_from=FY_START.isoformat(),
        date_to=FY_END.isoformat(),
        account_id=20,
        include_zero_balance=True,
        skip=0,
        take=50,
    )
    assert all(item["document_type"] != "opening_balance" for item in report["account_details"])
    assert report["account_details"][0]["credit"] == float(PERIOD_RECEIPT)
    # مانده افتتاحیه بستانکار + گردش دوره، بدون تکرار سند افتتاحیه
    assert report["account_details"][0]["balance"] == float(-(CAPITAL_OPENING + PERIOD_RECEIPT))
