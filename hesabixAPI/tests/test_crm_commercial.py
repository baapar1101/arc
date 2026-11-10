"""تجمیع فروش شخص بدون پایگاه داده و بدون مانده دوم."""
from app.services.crm_commercial import aggregate_commercial, known_line_cost


def _sale(**overrides):
    row = {
        "id": 1,
        "document_type": "invoice_sales",
        "is_proforma": False,
        "currency_id": 1,
        "document_date": "2026-01-01",
        "totals_net": 100,
        "lines": [],
        "receipt_ids": [],
    }
    row.update(overrides)
    return row


def test_net_sales_subtracts_returns_and_ignores_proforma():
    result = aggregate_commercial(
        [
            _sale(id=1, totals_net=200, receipt_ids=[9]),
            _sale(id=2, document_type="invoice_sales_return", totals_net=30),
            _sale(id=3, is_proforma=True, totals_net=999),
        ]
    )
    assert result["sales_total"] == 200
    assert result["returns_total"] == 30
    assert result["net_sales"] == 170
    assert result["receipt_ids"] == [9]
    assert result["mixed_currency"] is False


def test_mixed_currency_is_not_summed():
    result = aggregate_commercial(
        [
            _sale(currency_id=1, totals_net=100),
            _sale(id=2, currency_id=2, totals_net=50),
        ]
    )
    assert result["mixed_currency"] is True
    assert result["net_sales"] is None
    assert {row["currency_id"]: row["net_sales"] for row in result["currencies"]} == {1: 100, 2: 50}


def test_margin_uses_known_cost_only():
    assert known_line_cost({"unit_price": 80, "cost_price": None}, 1, None) is None
    result = aggregate_commercial(
        [
            _sale(
                id=1,
                totals_net=150,
                lines=[
                    {"product_id": 7, "product_name": "کالا", "quantity": 1, "extra_info": {"net": 100}, "ledger_line_cogs": 40},
                    {"product_id": 8, "product_name": "بی‌بها", "quantity": 1, "extra_info": {"net": 50, "unit_price": 50}},
                ],
            )
        ]
    )
    assert result["margin_amount"] == 60
    assert result["margin_complete"] is False


def test_repeat_suggestion_needs_two_invoices():
    line = {"product_id": 7, "product_name": "کالا", "quantity": 2, "extra_info": {"net": 10}, "ledger_line_cogs": 4}
    once = aggregate_commercial([_sale(id=1, lines=[line])])
    twice = aggregate_commercial([_sale(id=1, lines=[line]), _sale(id=2, document_date="2026-02-01", lines=[line])])
    assert once["repeat_products"] == []
    assert twice["repeat_products"][0]["invoice_count"] == 2
    assert twice["repeat_products"][0]["last_document_date"] == "2026-02-01"
