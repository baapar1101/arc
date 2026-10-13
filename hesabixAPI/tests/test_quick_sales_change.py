from __future__ import annotations

from types import SimpleNamespace

from app.services.invoice_service import _quick_sale_change_amount


def _invoice(total: int):
    return SimpleNamespace(extra_info={"totals": {"net": total}})


def test_quick_sale_change_is_zero_when_payments_do_not_exceed_total() -> None:
    assert _quick_sale_change_amount(
        _invoice(1_000_000),
        [{"amount": 400_000}, {"amount": 600_000}],
    ) == 0


def test_quick_sale_change_returns_overpayment() -> None:
    assert _quick_sale_change_amount(
        _invoice(1_000_000),
        [{"amount": 700_000}, {"amount": 450_000}],
    ) == 150_000


def test_quick_sale_change_uses_settlement_amount_for_foreign_payment() -> None:
    assert _quick_sale_change_amount(
        _invoice(1_000_000),
        [{"amount": 10, "settles_amount": 1_100_000}],
    ) == 100_000
