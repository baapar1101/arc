from copy import deepcopy
from datetime import date

import pytest
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.db import models
from adapters.db.models.business import BusinessField, BusinessType
from adapters.db.models.cash_register import CashRegister
from adapters.db.models.customer_club import (
    CustomerClubBalance,
    CustomerClubSettings,
    CustomerClubVoucher,
)
from adapters.db.models.document_monetization import DocumentUsagePolicy
from adapters.db.models.document_numbering import (
    BusinessDocumentNumberingSetting,
    DocumentCodeReservation,
    DocumentNumberCounter,
)
from app.core import cache
from app.services import customer_club_service, invoice_service

DAY = date(2026, 11, 11)


@pytest.fixture
def db(monkeypatch):
    monkeypatch.setattr(cache, "get_redis_client", lambda *args, **kwargs: None)
    monkeypatch.setattr(cache, "_cache_service", None)
    monkeypatch.setattr(
        customer_club_service, "check_customer_club_plugin_active", lambda *args: True
    )
    monkeypatch.setattr(customer_club_service, "user_can_redeem_loyalty_points", lambda *args: True)

    engine = create_engine("sqlite://")
    table_names = (
        "businesses",
        "currencies",
        "fiscal_years",
        "products",
        "documents",
        "document_lines",
        "invoice_item_lines",
        "document_usage_policies",
        "invoice_item_line_variant_allocations",
        "invoice_item_line_lot_allocations",
        "users",
        "accounts",
        "document_invoice_tag_links",
        "document_invoice_tags",
        "fa_assets",
        "cash_registers",
        "persons",
        "customer_club_settings",
        "customer_club_balances",
        "customer_club_vouchers",
        "customer_club_ledger",
        "customer_club_point_lots",
        "customer_club_invoice_snapshots",
        "customer_club_tiers",
        "customer_club_members",
        "customer_club_campaigns",
        "customer_club_campaign_members",
        "business_currencies",
        "workflows",
        "product_instances",
        "warehouse_documents",
        "warehouse_document_lines",
    )
    with Session(engine, autoflush=False) as session:
        tables = [models.Base.metadata.tables[name] for name in table_names]
        tables += [
            BusinessDocumentNumberingSetting.__table__,
            DocumentNumberCounter.__table__,
            DocumentCodeReservation.__table__,
        ]
        for table in tables:
            session.execute(CreateTable(table, include_foreign_key_constraints=[]))
        session.add_all(
            [
                models.Business(
                    id=1,
                    name="H24",
                    owner_id=1,
                    default_currency_id=1,
                    business_type=BusinessType.SHOP,
                    business_field=BusinessField.TRADING,
                ),
                models.Currency(id=1, name="Base", title="Base", symbol="B", code="B"),
                models.FiscalYear(
                    id=1, business_id=1, title="FY", is_last=True, start_date=DAY, end_date=DAY
                ),
                models.Product(id=1, business_id=1, code="P", name="P", track_inventory=False),
                models.Person(id=1, business_id=1, alias_name="Customer", person_types='["مشتری"]'),
                CashRegister(id=1, business_id=1, currency_id=1, name="Test cash"),
                DocumentUsagePolicy(
                    business_id=1, policy_type="free", title="Test", is_active=True
                ),
                CustomerClubSettings(
                    business_id=1,
                    enabled=True,
                    currency_value_per_point=1,
                    require_customer_person_type=False,
                ),
                CustomerClubBalance(business_id=1, person_id=1, balance_points=1000),
                *(
                    CustomerClubVoucher(
                        business_id=1,
                        person_id=1,
                        code=code.upper(),
                        reward_type="discount_fixed",
                        value=50,
                    )
                    for code in ("club-create", "club-without", "club-with", "club-no-header")
                ),
                *(
                    models.Account(code=code, name=code, account_type="asset")
                    for code in [
                        "50001",
                        "50002",
                        "50003",
                        "40003",
                        "70401",
                        "10102",
                        "10107",
                        "40001",
                        "20101",
                        "10104",
                        "70406",
                        "10106",
                        "70407",
                        "70408",
                        "10405",
                        "60205",
                        "10401",
                        "20201",
                        "10101",
                        "10301",
                        "10201",
                        "10105",
                        "10402",
                        "10202",
                    ]
                ),
            ]
        )
        session.commit()
        yield session
    engine.dispose()


def payload(code, gross, *, club=False):
    tax = gross // 10
    data = {
        "invoice_type": "invoice_sales",
        "currency_id": 1,
        "code": code,
        "document_date": DAY.isoformat(),
        "extra_info": {"person_id": 1, "post_inventory": False},
        "lines": [
            {
                "product_id": 1,
                "quantity": 1,
                "extra_info": {
                    "unit_price": gross,
                    "tax_rate": 10,
                    "tax_amount": tax,
                    "line_total": gross + tax,
                },
            }
        ],
    }
    if club:
        data.update(customer_club_voucher_code=code, loyalty_redemption_points=10)
    return data


def create(db, data):
    result = invoice_service.create_invoice(db, 1, 1, deepcopy(data), commit=False)
    db.commit()
    return result["data"]["id"]


def gl_lines(db, document_id):
    return sorted(
        (line.account.code, line.debit, line.credit, line.person_id)
        for line in db.scalars(select(models.DocumentLine).filter_by(document_id=document_id))
    )


def read_invoice(db, document_id):
    db.expire_all()
    doc = db.get(models.Document, document_id)
    totals = doc.extra_info["totals"]
    assert all(type(value) in (int, float) for value in totals.values())
    return totals, gl_lines(db, document_id)


@pytest.mark.parametrize("club", [False, True], ids=["taxable", "coupon-and-points"])
def test_invoice_rewrite_preserves_create_totals_and_gl(db, club):
    prefix = "club" if club else "plain"
    created = create(db, payload(f"{prefix}-create", 600, club=club))
    expected = read_invoice(db, created)
    discount, tax, net = (60, 54, 594) if club else (0, 60, 660)
    assert expected[0] == {
        "gross": 600,
        "discount": discount,
        "tax": tax,
        "net": net,
        "adjustments_net": 0,
        "adjustments_tax": 0,
    }
    assert expected[1] == [
        ("10401", net, 0, 1),
        ("20101", 0, tax, None),
        ("50001", 0, 600, None),
        *([("50003", 60, 0, None)] if club else []),
    ]
    print(f"CREATE {prefix}: {expected}")

    for mode in ("with", "without", "no-header"):
        code = f"{prefix}-{mode}"
        document_id = create(db, payload(code, 500, club=club))
        rewrite = payload(code, 600, club=club)
        if mode == "with":
            rewrite["extra_info"]["totals"] = {"gross": 600, "discount": 0, "tax": 60, "net": 660}
        elif mode == "no-header":
            del rewrite["extra_info"]
        print(f"UPDATE {prefix}, input={rewrite}")
        invoice_service.update_invoice(db, document_id, 1, rewrite)
        actual = read_invoice(db, document_id)
        print(f"UPDATE {prefix}, stored={actual}")
        assert actual == expected


def test_payment_only_preserves_rewritten_totals_and_gl(db):
    invoice_id = create(db, payload("payment", 500))
    invoice_service.update_invoice(db, invoice_id, 1, payload("payment", 600))
    before = read_invoice(db, invoice_id)

    invoice_service.update_invoice(
        db,
        invoice_id,
        1,
        {
            "payments": [
                {
                    "type": "cash_register",
                    "cash_register_id": 1,
                    "amount": 100,
                    "transaction_date": DAY.isoformat(),
                }
            ]
        },
    )

    assert read_invoice(db, invoice_id) == before
    receipt = db.scalars(select(models.Document).filter_by(document_type="receipt")).one()
    assert receipt.extra_info["invoice_id"] == invoice_id
    assert gl_lines(db, receipt.id) == [("10202", 100, 0, None), ("10401", 0, 100, 1)]
    remaining = invoice_service.calculate_invoice_remaining(db, 1, invoice_id)["remaining"]
    print(
        f"UPDATE payments-only: invoice={before}, receipt={gl_lines(db, receipt.id)}, remaining={remaining}"
    )
    assert remaining == 560


def test_rewrite_keeps_totals_calculated_by_global_discount(db):
    invoice_id = create(db, payload("global-discount", 500))
    rewrite = payload("global-discount", 600)
    rewrite["global_discount_amount"] = 50

    invoice_service.update_invoice(db, invoice_id, 1, rewrite)

    totals, ledger = read_invoice(db, invoice_id)
    assert totals == {
        "gross": 600,
        "discount": 50,
        "tax": 55,
        "net": 605,
        "adjustments_net": 0,
        "adjustments_tax": 0,
    }
    assert ledger == [
        ("10401", 605, 0, 1),
        ("20101", 0, 55, None),
        ("50001", 0, 600, None),
        ("50003", 50, 0, None),
    ]
