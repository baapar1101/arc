"""تست مبلغ قابل پرداخت فاکتور با اضافات/کسورات."""

from decimal import Decimal

from app.services.invoice_adjustments_service import (
    payable_total_from_extra_info,
    payable_total_from_totals_dict,
    total_with_tax_from_totals_dict,
)


def test_payable_total_includes_shipping_addition() -> None:
    totals = {
        "gross": 400_000,
        "discount": 0,
        "tax": 0,
        "net": 400_000,
        "adjustments_net": 100_000,
        "adjustments_tax": 0,
    }
    assert payable_total_from_totals_dict(totals) == Decimal("500000.00")
    assert total_with_tax_from_totals_dict(totals) == Decimal("500000.00")


def test_payable_total_with_adjustment_tax() -> None:
    totals = {
        "gross": 1_000_000,
        "discount": 0,
        "tax": 90_000,
        "net": 1_090_000,
        "adjustments_net": 50_000,
        "adjustments_tax": 4_500,
    }
    assert payable_total_from_totals_dict(totals) == Decimal("1144500.00")


def test_payable_total_with_deduction() -> None:
    totals = {
        "gross": 200_000,
        "discount": 0,
        "tax": 0,
        "net": 200_000,
        "adjustments_net": -30_000,
        "adjustments_tax": 0,
    }
    assert payable_total_from_totals_dict(totals) == Decimal("170000.00")


def test_payable_total_from_extra_info() -> None:
    extra = {
        "totals": {
            "net": 400_000,
            "adjustments_net": 100_000,
            "adjustments_tax": 0,
        }
    }
    assert payable_total_from_extra_info(extra) == Decimal("500000.00")


def test_payable_total_fallback_without_net() -> None:
    totals = {
        "gross": 400_000,
        "discount": 0,
        "tax": 0,
        "adjustments_net": 100_000,
        "adjustments_tax": 0,
    }
    assert payable_total_from_totals_dict(totals) == Decimal("500000.00")
