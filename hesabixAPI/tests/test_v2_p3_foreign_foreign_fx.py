"""V2-P3: تسویه/انتقال فرعی↔فرعی با E1 (دو نرخ به پایه) و E2 (سند پایه)."""
from __future__ import annotations

from decimal import Decimal
from types import SimpleNamespace
from datetime import datetime, timezone

import pytest

from app.core.responses import ApiError
from app.services.cross_currency_settlement_service import (
	build_fx_settlement_extra,
	resolve_cross_currency_payment_plan,
	resolve_cross_currency_transfer_plan,
)


def test_foreign_to_foreign_payment_plan_via_two_rates_to_base(monkeypatch):
	invoice = SimpleNamespace(
		currency_id=2,
		document_date=datetime(2024, 1, 15, tzinfo=timezone.utc),
		extra_info={"fx": {"rate": "60000"}},
	)
	payment = {
		"transaction_type": "bank",
		"bank_id": 1,
		"amount": Decimal("90"),  # EUR
		"settles_amount": Decimal("100"),  # USD
		"invoice_rate_to_base": Decimal("60000"),
		"payment_rate_to_base": Decimal("65000"),
	}

	monkeypatch.setattr(
		"app.services.cross_currency_settlement_service.business_is_multi_currency",
		lambda db, bid: True,
	)
	monkeypatch.setattr(
		"app.services.cross_currency_settlement_service.get_payment_item_account_currency_id",
		lambda db, p: 3,  # EUR
	)

	class FakeBiz:
		default_currency_id = 1  # IRR

	class FakeDB:
		def get(self, model, pk):
			return FakeBiz()

	monkeypatch.setattr(
		"app.services.cross_currency_settlement_service.get_currency_quant_and_round",
		lambda db, cid: (Decimal("1"), True),
	)

	plan = resolve_cross_currency_payment_plan(
		FakeDB(), business_id=1, invoice=invoice, payment_item=payment
	)
	assert plan is not None
	assert plan["document_currency_id"] == 1
	assert plan["ar_base"] == Decimal("6000000")  # 100 * 60000
	assert plan["cash_base"] == Decimal("5850000")  # 90 * 65000
	assert plan["fx_diff"] == Decimal("150000")
	extra = build_fx_settlement_extra(plan)
	assert extra["invoice_rate_to_base"] == "60000"
	assert extra["payment_rate_to_base"] == "65000"


def test_foreign_to_foreign_transfer_plan(monkeypatch):
	monkeypatch.setattr(
		"app.services.cross_currency_settlement_service.business_is_multi_currency",
		lambda db, bid: True,
	)
	monkeypatch.setattr(
		"app.services.cross_currency_settlement_service.resolve_transfer_account_currency",
		lambda db, tp, aid: 2 if int(aid) == 10 else 3,
	)

	class FakeBiz:
		default_currency_id = 1

	class FakeDB:
		def get(self, model, pk):
			return FakeBiz()

	monkeypatch.setattr(
		"app.services.cross_currency_settlement_service.get_currency_quant_and_round",
		lambda db, cid: (Decimal("0.01"), True),
	)

	plan = resolve_cross_currency_transfer_plan(
		FakeDB(),
		business_id=1,
		source_type="bank",
		source_id=10,
		destination_type="bank",
		destination_id=20,
		source_amount=Decimal("100"),
		destination_amount=Decimal("90"),
		fx_rate=None,
		source_rate_to_base=Decimal("60000"),
		destination_rate_to_base=Decimal("65000"),
	)
	assert plan is not None
	assert plan["document_currency_id"] == 1
	assert plan["source_base"] == Decimal("6000000.00")
	assert plan["destination_base"] == Decimal("5850000.00")
	assert plan["fx_diff"] == Decimal("150000.00")


def test_cross_currency_no_longer_raises_base_required(monkeypatch):
	invoice = SimpleNamespace(
		currency_id=2,
		document_date=datetime(2024, 1, 15, tzinfo=timezone.utc),
		extra_info={},
	)
	payment = {
		"transaction_type": "bank",
		"bank_id": 1,
		"amount": 90,
		"settles_amount": 100,
		"invoice_rate_to_base": "60000",
		"payment_rate_to_base": "65000",
	}
	monkeypatch.setattr(
		"app.services.cross_currency_settlement_service.business_is_multi_currency",
		lambda db, bid: True,
	)
	monkeypatch.setattr(
		"app.services.cross_currency_settlement_service.get_payment_item_account_currency_id",
		lambda db, p: 3,
	)

	class FakeBiz:
		default_currency_id = 1

	class FakeDB:
		def get(self, model, pk):
			return FakeBiz()

	monkeypatch.setattr(
		"app.services.cross_currency_settlement_service.get_currency_quant_and_round",
		lambda db, cid: (Decimal("1"), True),
	)

	plan = resolve_cross_currency_payment_plan(
		FakeDB(), business_id=1, invoice=invoice, payment_item=payment
	)
	assert plan is not None
	# اطمینان از حذف خطای قدیمی
	with pytest.raises(ApiError):
		# MC خاموش هنوز mismatch می‌دهد
		monkeypatch.setattr(
			"app.services.cross_currency_settlement_service.business_is_multi_currency",
			lambda db, bid: False,
		)
		resolve_cross_currency_payment_plan(
			FakeDB(), business_id=1, invoice=invoice, payment_item=payment
		)
