"""تست‌های واحد P2 / P2.5 تسعیر خطوط و جمع دوگانه فاکتور."""
from __future__ import annotations

from decimal import Decimal
from types import SimpleNamespace

from app.services.document_line_fx_service import (
	compute_base_amounts,
	parse_fx_rate_from_extra,
	quantize_money,
	build_invoice_dual_totals,
)


def test_parse_fx_rate_from_extra_ok():
	assert parse_fx_rate_from_extra({"fx": {"rate": "1600000", "mode": "auto"}}) == Decimal("1600000")


def test_parse_fx_rate_from_extra_skipped():
	assert parse_fx_rate_from_extra({"fx": {"skipped": True, "reason": "no_rate"}}) is None


def test_parse_fx_rate_from_extra_base_mode():
	assert parse_fx_rate_from_extra({"fx": {"rate": "1", "mode": "base"}}) == Decimal("1")


def test_compute_base_amounts_irr_no_decimal():
	debit_base, credit_base = compute_base_amounts(
		debit=Decimal("100"),
		credit=Decimal("0"),
		rate=Decimal("1600000"),
		base_quant=Decimal("1"),
		round_on=True,
	)
	assert debit_base == Decimal("160000000")
	assert credit_base == Decimal("0")


def test_compute_base_amounts_with_cents():
	debit_base, credit_base = compute_base_amounts(
		debit=Decimal("10.55"),
		credit=Decimal("0"),
		rate=Decimal("2.5"),
		base_quant=Decimal("0.01"),
		round_on=True,
	)
	assert debit_base == Decimal("26.38")  # 26.375 → 26.38 HALF_UP
	assert credit_base == Decimal("0.00")


def test_quantize_money_no_round():
	assert quantize_money(Decimal("1.234567"), Decimal("0.01"), round_on=False) == Decimal("1.234567")


def test_build_invoice_dual_totals_base_currency_hides_dual(monkeypatch):
	"""وقتی ارز سند = پایه، show_dual باید false باشد."""

	class FakeDB:
		def get(self, model, pk):
			return None

	doc = SimpleNamespace(
		id=1,
		business_id=1,
		currency_id=1,
		document_date=None,
		registered_at=None,
		extra_info={
			"totals": {"gross": 100, "discount": 0, "tax": 0, "net": 100, "adjustments_net": 0, "adjustments_tax": 0},
			"fx": {"rate": "1", "mode": "base", "base_currency_id": 1, "document_currency_id": 1},
		},
	)
	biz = SimpleNamespace(id=1, default_currency_id=1)

	def fake_quant(db, cid):
		return Decimal("1"), True

	monkeypatch.setattr(
		"app.services.document_line_fx_service.get_currency_quant_and_round",
		fake_quant,
	)
	out = build_invoice_dual_totals(FakeDB(), doc, business=biz)
	assert out["show_dual"] is False
	assert out["is_foreign_currency"] is False
	assert out["base"]["payable"] == 100.0


def test_build_invoice_dual_totals_foreign_shows_dual(monkeypatch):
	class FakeDB:
		def get(self, model, pk):
			return None

	doc = SimpleNamespace(
		id=2,
		business_id=1,
		currency_id=2,
		document_date=None,
		registered_at=None,
		extra_info={
			"totals": {"gross": 100, "discount": 0, "tax": 9, "net": 109, "adjustments_net": 0, "adjustments_tax": 0},
			"fx": {
				"rate": "1600000",
				"mode": "auto",
				"base_currency_id": 1,
				"document_currency_id": 2,
			},
		},
	)
	biz = SimpleNamespace(id=1, default_currency_id=1)

	def fake_quant(db, cid):
		return Decimal("1"), True

	monkeypatch.setattr(
		"app.services.document_line_fx_service.get_currency_quant_and_round",
		fake_quant,
	)
	out = build_invoice_dual_totals(FakeDB(), doc, business=biz)
	assert out["show_dual"] is True
	assert out["is_foreign_currency"] is True
	assert out["foreign"]["payable"] == 109.0
	assert out["base"]["payable"] == 174400000.0  # 109 * 1600000
	assert out["base"]["rate"] == 1600000.0
