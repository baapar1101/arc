"""V2-P4: دریافت/پرداخت مستقل بین‌ارزی → سند پایه + fx_settlement + خطوط تسعیر."""
from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
from types import SimpleNamespace

from app.services.cross_currency_settlement_service import (
	prepare_standalone_receipt_payment_cross_currency,
)


def test_standalone_receipt_usd_person_eur_bank_rewrites_to_base(monkeypatch):
	monkeypatch.setattr(
		"app.services.cross_currency_settlement_service.business_is_multi_currency",
		lambda db, bid: True,
	)
	monkeypatch.setattr(
		"app.services.cross_currency_settlement_service.get_payment_item_account_currency_id",
		lambda db, p: 3,  # EUR bank
	)

	class FakeBiz:
		default_currency_id = 1  # IRR

	class FakeDB:
		def get(self, model, pk):
			return FakeBiz()

	def fake_rate(db, business_id, currency_id, as_of):
		# 1 USD = 60000 IRR, 1 EUR = 65000 IRR
		rates = {2: Decimal("60000"), 3: Decimal("65000"), 1: Decimal("1")}
		return {"rate": rates[int(currency_id)]}

	monkeypatch.setattr(
		"app.services.cross_currency_settlement_service.resolve_rate_to_base",
		fake_rate,
	)
	monkeypatch.setattr(
		"app.services.cross_currency_settlement_service.get_currency_quant_and_round",
		lambda db, cid: (Decimal("1"), True),
	)

	data = {
		"currency_id": 2,  # تسویه USD
		"document_date": datetime(2024, 1, 15, tzinfo=timezone.utc),
		"person_lines": [{"person_id": 1, "amount": 100}],
		"account_lines": [
			{
				"transaction_type": "bank",
				"bank_id": 10,
				"amount": 90,  # EUR
				"settles_amount": 100,  # USD
			}
		],
	}
	out = prepare_standalone_receipt_payment_cross_currency(
		FakeDB(), 1, data, is_receipt=True
	)
	assert out["currency_id"] == 1  # E2: پایه
	assert out["extra_info"]["cross_currency"] is True
	assert out["extra_info"]["settles_currency_id"] == 2
	al = out["account_lines"][0]
	assert al["amount"] == 5850000.0  # 90 * 65000
	assert al["account_currency_amount"] == 90.0
	assert al["account_currency_id"] == 3
	pl = out["person_lines"][0]
	assert pl["amount"] == 6000000.0  # 100 * 60000
	assert "fx_settlement" in pl["extra_info"]
	assert out["fx_adjustment_lines"]  # زیان تسعیر
	assert abs(
		Decimal(str(pl["amount"]))
		- Decimal(str(al["amount"]))
		- Decimal(str(out["fx_adjustment_lines"][0]["amount"]))
	) < 1


def test_standalone_skips_when_already_stamped(monkeypatch):
	data = {
		"currency_id": 1,
		"extra_info": {"cross_currency": True},
		"fx_adjustment_lines": [{"account_code": "70801", "amount": 1}],
		"person_lines": [{"amount": 1}],
		"account_lines": [{"amount": 1, "account_currency_amount": 10}],
	}
	out = prepare_standalone_receipt_payment_cross_currency(
		SimpleNamespace(), 1, data, is_receipt=True
	)
	assert out is data
