"""آمار داشبورد/لانچر: فروش واقعی به ارز پایه با تسعیر و برگشت از فروش."""
from __future__ import annotations

from decimal import Decimal
from types import SimpleNamespace

from app.services.business_dashboard_service import (
    _currency_payload,
    _net_from_document,
    _signed_net_for_type,
    aggregate_invoice_totals_in_base,
)
from app.services.invoice_service import (
    INVOICE_PURCHASE,
    INVOICE_PURCHASE_RETURN,
    INVOICE_SALES,
    INVOICE_SALES_RETURN,
)


def _doc(**kwargs):
    data = dict(
        id=1,
        business_id=1,
        currency_id=1,
        document_date=None,
        registered_at=None,
        is_proforma=False,
        extra_info={},
        document_type=INVOICE_SALES,
    )
    data.update(kwargs)
    return SimpleNamespace(**data)


def test_net_from_document_reads_totals():
    assert _net_from_document(_doc(extra_info={"totals": {"net": "1500.5"}})) == Decimal("1500.5")
    assert _net_from_document(_doc(extra_info=None)) == Decimal(0)
    assert _net_from_document(_doc(extra_info={"totals": {}})) == Decimal(0)


def test_signed_net_sales_return_is_negative():
    sales, purchases, count = _signed_net_for_type(INVOICE_SALES, Decimal("10"))
    assert (sales, purchases, count) == (Decimal("10"), Decimal(0), 1)
    sales, purchases, count = _signed_net_for_type(INVOICE_SALES_RETURN, Decimal("3"))
    assert (sales, purchases, count) == (Decimal("-3"), Decimal(0), 0)


def test_currency_payload_includes_unit_and_decimals():
    cur = SimpleNamespace(id=7, code="USD", title="دلار", symbol="$", decimal_places=2)
    assert _currency_payload(cur) == {
        "id": 7,
        "code": "USD",
        "title": "دلار",
        "symbol": "$",
        "decimal_places": 2,
    }
    assert _currency_payload(None) is None


def test_aggregate_converts_fx_and_subtracts_returns(monkeypatch):
    def fake_to_base(_db, doc, amount, **_kwargs):
        extra = doc.extra_info or {}
        fx = extra.get("fx") if isinstance(extra.get("fx"), dict) else {}
        rate = Decimal(str(fx.get("rate") or 1))
        return Decimal(str(amount)) * rate

    monkeypatch.setattr(
        "app.services.business_dashboard_service.amount_in_document_currency_to_base",
        fake_to_base,
    )
    docs = [
        _doc(
            id=1,
            extra_info={"totals": {"net": 10}, "fx": {"rate": "1600000"}},
            document_type=INVOICE_SALES,
        ),
        _doc(
            id=2,
            extra_info={"totals": {"net": 1}, "fx": {"rate": "1600000"}},
            document_type=INVOICE_SALES_RETURN,
        ),
        _doc(
            id=3,
            extra_info={"totals": {"net": 500000}},
            document_type=INVOICE_SALES,
        ),
        _doc(
            id=4,
            extra_info={"totals": {"net": 200}},
            document_type=INVOICE_PURCHASE,
        ),
        _doc(
            id=5,
            extra_info={"totals": {"net": 50}},
            document_type=INVOICE_PURCHASE_RETURN,
        ),
        _doc(
            id=6,
            is_proforma=True,
            extra_info={"totals": {"net": 999999}},
            document_type=INVOICE_SALES,
        ),
    ]
    sales, purchases, count = aggregate_invoice_totals_in_base(
        None, docs, rate_cache={}, base_currency_by_business={}
    )
    # 10 USD × 1_600_000 − 1 USD × 1_600_000 + 500_000 ریال
    assert sales == Decimal("14900000")
    assert purchases == Decimal("150")
    assert count == 2


def test_aggregate_differs_per_business_documents(monkeypatch):
    monkeypatch.setattr(
        "app.services.business_dashboard_service.amount_in_document_currency_to_base",
        lambda _db, _doc, amount, **_kw: Decimal(str(amount)),
    )
    biz_a = [_doc(id=1, extra_info={"totals": {"net": 25}}, document_type=INVOICE_SALES)]
    biz_b = [
        _doc(id=2, extra_info={"totals": {"net": 100}}, document_type=INVOICE_SALES),
        _doc(id=3, extra_info={"totals": {"net": 40}}, document_type=INVOICE_SALES),
    ]
    sales_a, _, count_a = aggregate_invoice_totals_in_base(None, biz_a)
    sales_b, _, count_b = aggregate_invoice_totals_in_base(None, biz_b)
    assert (sales_a, count_a) == (Decimal("25"), 1)
    assert (sales_b, count_b) == (Decimal("140"), 2)
    assert sales_a != sales_b
