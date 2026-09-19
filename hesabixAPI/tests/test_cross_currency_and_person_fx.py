"""تست‌های P5 مانده per ارز و طرح تسویه بین‌ارزی P3."""
from __future__ import annotations

from decimal import Decimal
from types import SimpleNamespace

import pytest

from app.services.cross_currency_settlement_service import (
	build_fx_settlement_extra,
	resolve_cross_currency_payment_plan,
)
from app.services.document_line_fx_service import compute_base_amounts


def test_build_fx_settlement_extra_shape():
	plan = {
		"invoice_currency_id": 2,
		"payment_currency_id": 1,
		"base_currency_id": 1,
		"settles_amount": Decimal("200"),
		"payment_amount": Decimal("280000000"),
		"tx_rate": Decimal("1400000"),
		"ar_base": Decimal("300000000"),
		"cash_base": Decimal("280000000"),
		"fx_diff": Decimal("20000000"),
		"mode": "manual",
	}
	extra = build_fx_settlement_extra(plan)
	assert extra["settles_currency_id"] == 2
	assert extra["settles_amount"] == "200"
	assert extra["fx_diff"] == "20000000"


def test_compute_base_amounts_for_transfer_line():
	d, c = compute_base_amounts(
		debit=Decimal("0"),
		credit=Decimal("1000"),
		rate=Decimal("1600000"),
		base_quant=Decimal("1"),
		round_on=True,
	)
	assert d == Decimal("0")
	assert c == Decimal("1600000000")


def test_resolve_cross_currency_rejects_without_mc(monkeypatch):
	class FakeDB:
		pass

	invoice = SimpleNamespace(currency_id=2, extra_info={"fx": {"rate": "1500000"}})
	payment = {"transaction_type": "bank", "bank_id": 1, "amount": 280000000, "settles_amount": 200}

	monkeypatch.setattr(
		"app.services.cross_currency_settlement_service.business_is_multi_currency",
		lambda db, bid: False,
	)
	monkeypatch.setattr(
		"app.services.cross_currency_settlement_service.get_payment_item_account_currency_id",
		lambda db, p: 1,
	)

	from app.core.responses import ApiError

	with pytest.raises(ApiError) as ei:
		resolve_cross_currency_payment_plan(
			FakeDB(), business_id=1, invoice=invoice, payment_item=payment
		)
	detail = ei.value.detail if isinstance(ei.value.detail, dict) else {}
	err = detail.get("error") if isinstance(detail, dict) else {}
	code = err.get("code") if isinstance(err, dict) else None
	assert code == "PAYMENT_CURRENCY_MISMATCH"
