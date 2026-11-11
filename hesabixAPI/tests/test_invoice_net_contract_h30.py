from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.db import models
from adapters.db.models.business import BusinessField, BusinessType
from adapters.db.models.customer_club import CustomerClubBalance, CustomerClubSettings, CustomerClubVoucher
from adapters.db.models.document_monetization import DocumentUsagePolicy
from adapters.db.models.person import Person, PersonType
from app.core import cache
from app.services.customer_club_service import (
    _apply_club_discount_to_totals,
    _basis_net_and_total_from_document,
    maybe_apply_loyalty_redemption_to_invoice_payload,
)
from app.services.invoice_adjustments_service import (
    payable_total_from_totals_dict,
    total_with_tax_from_totals_dict,
)
from app.services.invoice_service import create_invoice
from app.services.person_share_link_service import _public_invoice_financials_from_extra_info

ACCOUNT_CODES = (
    "10401", "10405", "10102", "10104", "10106", "10107",
    "20101", "40001", "40003", "50001", "50002", "50003",
    "60205", "70401", "70406", "70407", "70408",
)


@pytest.fixture
def db(monkeypatch):
    for key, value in {
        "_redis_config": {"enabled": False},
        "_redis_config_expires_at": float("inf"),
        "_redis_retry_at": float("inf"),
        "_redis_client": None,
        "_cache_service": None,
    }.items():
        monkeypatch.setattr(cache, key, value)
    monkeypatch.setattr(
        "app.services.customer_club_service.check_customer_club_plugin_active",
        lambda *args, **kwargs: True,
    )
    monkeypatch.setattr(
        "app.services.customer_club_service.user_can_redeem_loyalty_points",
        lambda *args, **kwargs: True,
    )
    monkeypatch.setattr(
        "app.services.customer_club_service.commit_loyalty_redemption_for_sales_invoice",
        lambda *args, **kwargs: None,
    )
    engine = create_engine("sqlite://")
    names = (
        "businesses", "currencies", "fiscal_years", "products", "documents", "document_lines",
        "invoice_item_lines", "document_usage_policies", "invoice_item_line_variant_allocations",
        "invoice_item_line_lot_allocations", "users", "accounts", "persons", "fa_assets",
        "customer_club_settings", "customer_club_balances", "customer_club_rewards",
        "customer_club_campaigns", "customer_club_vouchers", "customer_club_ledger",
        "customer_club_point_lots",
    )
    day = date(2026, 11, 11)
    with Session(engine, autoflush=False) as session:
        for name in names:
            session.execute(CreateTable(models.Base.metadata.tables[name]))
        session.add_all([
            models.Business(
                id=1, name="H30", owner_id=1, default_currency_id=1,
                business_type=BusinessType.SHOP, business_field=BusinessField.TRADING,
            ),
            models.FiscalYear(id=1, business_id=1, title="H30", start_date=day, end_date=day, is_last=True),
            models.Currency(id=1, name="IRR", title="IRR", symbol="R", code="IRR", decimal_places=2),
            models.Product(id=1, business_id=1, code="P", name="P", track_inventory=False),
            DocumentUsagePolicy(business_id=1, policy_type="free", title="Test", is_active=True),
            Person(
                id=1, business_id=1, alias_name="C",
                person_types=f'["{PersonType.CUSTOMER.value}"]',
            ),
            *(models.Account(id=i + 1, business_id=None, code=code, name=code, account_type="system")
              for i, code in enumerate(ACCOUNT_CODES)),
            CustomerClubSettings(
                business_id=1, enabled=True, currency_value_per_point=Decimal("1"),
            ),
            CustomerClubBalance(business_id=1, person_id=1, balance_points=Decimal("100")),
            CustomerClubVoucher(
                business_id=1, person_id=1, code="C50", status="issued",
                value=Decimal("50"), reward_type="discount_amount",
            ),
        ])
        session.commit()
        yield session
    engine.dispose()


def sale_totals():
    return {"gross": 500, "discount": 0, "tax": 50, "net": 550}


def test_club_discount_writes_net_including_tax():
    totals = sale_totals()
    _apply_club_discount_to_totals(totals, Decimal("50"))
    assert totals["discount"] == 50.0
    assert totals["tax"] == 45.0
    assert totals["net"] == 495.0
    assert payable_total_from_totals_dict(totals) == total_with_tax_from_totals_dict(totals) == Decimal("495.00")


def test_combined_coupon_and_points_match_gl_formula(db):
    totals = sale_totals()
    extra = {}
    maybe_apply_loyalty_redemption_to_invoice_payload(
        db, 1, "invoice_sales", False, 1, totals, extra,
        {"customer_club_voucher_code": "C50", "loyalty_redemption_points": 10},
        1,
    )
    assert totals["discount"] == 60.0
    assert totals["tax"] == 44.0
    assert totals["net"] == 484.0
    assert payable_total_from_totals_dict(totals) == Decimal("484.00")
    assert total_with_tax_from_totals_dict(totals) == Decimal("484.00")


def test_create_invoice_ar_matches_payable_for_combined_club(db):
    payload = {
        "invoice_type": "invoice_sales",
        "document_date": "2026-11-11",
        "currency_id": 1,
        "code": "H30",
        "is_proforma": False,
        "customer_club_voucher_code": "C50",
        "loyalty_redemption_points": 10,
        "extra_info": {"person_id": 1, "post_inventory": False},
        "lines": [{
            "product_id": 1,
            "quantity": 1,
            "extra_info": {"unit_price": 500, "tax_rate": 10, "tax_amount": 50, "line_total": 550},
        }],
    }
    result = create_invoice(db, 1, 1, payload, commit=False)
    document = db.get(models.Document, result["data"]["id"])
    totals = document.extra_info["totals"]
    payable = payable_total_from_totals_dict(totals)
    gl = total_with_tax_from_totals_dict(totals)
    ar = db.query(models.Account).filter_by(code="10401").one()
    debit = sum(
        (line.debit or 0)
        for line in db.query(models.DocumentLine).filter_by(document_id=document.id, account_id=ar.id)
    )
    assert totals["net"] == 484.0
    assert payable == gl == Decimal("484.00")
    assert Decimal(str(debit)) == Decimal("484")


def test_person_display_does_not_double_count_tax():
    extra = {"totals": {"gross": 500, "discount": 0, "tax": 50, "net": 550}}
    assert _public_invoice_financials_from_extra_info(extra)["total"] == 550.0
    old_coupon = {"totals": {"gross": 500, "discount": 50, "tax": 45, "net": 450}}
    assert _public_invoice_financials_from_extra_info(old_coupon)["total"] == 495.0


def test_loyalty_earn_total_with_tax_does_not_add_tax_twice(db):
    document = models.Document(
        extra_info={"totals": {"gross": 500, "discount": 0, "tax": 50, "net": 550}},
    )
    net_b, total_b = _basis_net_and_total_from_document(db, document)
    assert net_b == Decimal("550")
    assert total_b == Decimal("550.00")
