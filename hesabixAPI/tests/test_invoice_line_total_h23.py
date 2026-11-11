from copy import deepcopy
from datetime import date

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.db import models
from adapters.db.models.business import BusinessField, BusinessType
from adapters.db.models.document_monetization import DocumentUsagePolicy
from app.core import cache
from app.core.responses import ApiError
from app.services.invoice_service import create_invoice, update_invoice


@pytest.fixture
def db(monkeypatch):
    for key, value in {"_redis_config": {"enabled": False}, "_redis_config_expires_at": float("inf"),
                       "_redis_retry_at": float("inf"), "_redis_client": None, "_cache_service": None}.items():
        monkeypatch.setattr(cache, key, value)
    engine = create_engine("sqlite://")
    names = ("businesses", "currencies", "fiscal_years", "products", "documents", "document_lines",
             "invoice_item_lines", "document_usage_policies", "invoice_item_line_variant_allocations",
             "invoice_item_line_lot_allocations", "users", "accounts", "document_invoice_tag_links", "document_invoice_tags", "fa_assets")
    day = date(2026, 11, 11)
    with Session(engine, autoflush=False) as db:
        for name in names:
            db.execute(CreateTable(models.Base.metadata.tables[name]))
        db.add_all([
            models.Business(id=1, name="H23", owner_id=1, default_currency_id=1,
                            business_type=BusinessType.SHOP, business_field=BusinessField.TRADING),
            models.FiscalYear(id=1, business_id=1, title="H23", start_date=day, end_date=day, is_last=True),
            DocumentUsagePolicy(business_id=1, policy_type="free", title="Test", is_active=True),
            *(models.Currency(id=i, name=str(i), title=str(i), symbol="X", code=f"X{i}", decimal_places=dp)
              for i, dp in [(1, 2), (2, 8)]),
            *(models.Product(id=i, business_id=1, code=str(i), name=str(i), track_inventory=False,
                             main_unit="carton", secondary_unit="each", unit_conversion_factor=20) for i in (1, 2)),
        ])
        db.commit()
        yield db
    engine.dispose()


def line(qty, price, total, product=1):
    return {"product_id": product, "quantity": qty, "extra_info": {
        "unit": "each", "unit_price": price, "line_total": total}}


def create(db, lines, *, currency=1, discount=0):
    db.get(models.Business, 1).default_currency_id = currency
    payload = {"invoice_type": "invoice_sales", "document_date": "2026-11-11", "currency_id": currency,
               "code": "H23", "is_proforma": True, "global_discount_amount": discount,
               "extra_info": {"person_id": 1, "post_inventory": False}, "lines": deepcopy(lines)}
    return create_invoice(db, 1, 1, payload, commit=False)["data"]["id"]


@pytest.mark.parametrize("qty,price,total,currency,discount", [
    (2, 250, 250, 1, 0), (2, 250, 500, 1, 0), (1, 100, 90, 1, 10), (7, 14.29, 100, 1, 0),
    (100, 0.07, 7.000000000000001, 1, 0),
    (3, "33333333.33666667", "100000000.01", 2, 0),
])
def test_create_line_totals(db, qty, price, total, currency, discount):
    if total == 250:
        with pytest.raises(ApiError) as error:
            create(db, [line(qty, price, total)], currency=currency)
        assert (error.value.code, error.value.status_code) == ("INCONSISTENT_LINE_TOTAL", 422)
        assert db.query(models.Document).count() == 0
    else:
        assert create(db, [line(qty, price, total)], currency=currency, discount=discount)


@pytest.mark.parametrize("mode", ["reorder", "append", "unchanged", "discount", "bad_append"])
def test_update_line_totals(db, mode):
    first, second = line(2, 250, 500), line(2, 250.01, 500.02, 2)
    original = [line(1, 100, 90)] if mode == "discount" else [first]
    did = create(db, [first, second] if mode == "reorder" else original, discount=10 if mode == "discount" else 0)
    db.commit()
    lines = {"reorder": [line(2, 250.01, 499.98, 2), first], "append": [first, line(3, 250, 750)],
             "bad_append": [first, line(3, 250, 500)]}.get(mode, original)
    data = {"lines": lines, **({"code": "H23-EDIT"} if mode == "discount" else {})}
    if mode in {"reorder", "bad_append"}:
        with pytest.raises(ApiError) as error:
            update_invoice(db, did, 1, data)
        assert (error.value.code, error.value.status_code) == ("INCONSISTENT_LINE_TOTAL", 422)
    else:
        result = update_invoice(db, did, 1, data)
        assert len(result["product_lines"]) == len(lines)
