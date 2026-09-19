"""تست محاسبات اجرای حقوق."""

from __future__ import annotations

from decimal import Decimal
from types import SimpleNamespace

from app.services.payroll_service import (
	_compute_amounts_from_items,
	_resolve_item_amount,
	_round_amount,
)


def _item(kind: str, affects_gross: bool = True, calc: str = "manual", **kwargs):
	return SimpleNamespace(
		item_kind=kind,
		affects_gross=affects_gross,
		calculation_type=calc,
		default_amount=kwargs.get("default_amount"),
		percent_value=kwargs.get("percent_value"),
		code=kwargs.get("code", "x"),
	)


def _settings(round_to: int = 0):
	return SimpleNamespace(round_amounts_to=round_to, allow_negative_net=False)


def test_round_amount_integer():
	assert _round_amount(Decimal("1234.56"), 0) == Decimal("1235")


def test_compute_line_totals():
	earning = _item("earning", affects_gross=True)
	deduction = _item("deduction", affects_gross=False)
	employer = _item("employer_cost", affects_gross=False)
	pairs = [(earning, Decimal("10000000")), (deduction, Decimal("1500000")), (employer, Decimal("800000"))]
	gross, ded, net, emp = _compute_amounts_from_items(pairs, _settings())
	assert gross == Decimal("10000000")
	assert ded == Decimal("1500000")
	assert net == Decimal("8500000")
	assert emp == Decimal("800000")


def test_resolve_percent_of_base():
	item_def = _item("deduction", calc="percent_of_base", percent_value=Decimal("7"))
	amt, computed = _resolve_item_amount(item_def, None, Decimal("10000000"), Decimal("0"))
	assert computed is True
	assert amt == Decimal("700000")


def test_resolve_explicit_override():
	item_def = _item("earning", calc="fixed", default_amount=Decimal("1"))
	amt, computed = _resolve_item_amount(item_def, "5000", Decimal("0"), Decimal("0"))
	assert computed is False
	assert amt == Decimal("5000")
