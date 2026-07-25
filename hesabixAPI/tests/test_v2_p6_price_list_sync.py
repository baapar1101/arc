"""V2-P6: همگام اختیاری PriceList هنگام sync قیمت FX کالا."""
from __future__ import annotations

from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import MagicMock

from app.services.product_fx_price_service import (
	resolve_default_price_list_id,
	sync_price_list_from_product_base,
)


def test_resolve_default_price_list_prefers_quick_sales():
	qs = SimpleNamespace(default_price_list_id=7)
	pl = SimpleNamespace(id=7, business_id=1, is_active=True)

	db = MagicMock()
	db.query.return_value.filter.return_value.first.return_value = qs
	db.get.return_value = pl

	assert resolve_default_price_list_id(db, 1) == 7


def test_sync_price_list_from_product_base_upserts_sales(monkeypatch):
	product = SimpleNamespace(
		id=10,
		business_id=1,
		base_sales_price=Decimal("6000000"),
	)
	biz = SimpleNamespace(default_currency_id=1)
	pl = SimpleNamespace(id=3, business_id=1, is_active=True)

	db = MagicMock()
	db.get.side_effect = lambda model, pk: {
		(type(pl), 3): pl,
		(type(biz), 1): biz,
	}.get((model, pk), biz if pk == 1 else pl)

	# resolve_default → 3
	monkeypatch.setattr(
		"app.services.product_fx_price_service.resolve_default_price_list_id",
		lambda db, bid: 3,
	)

	calls = {}

	def fake_upsert(**kwargs):
		calls.update(kwargs)
		return {"action": "created", "price_item_id": 99, "currency_id": 1, "before": None, "after": "6000000"}

	monkeypatch.setattr(
		"app.services.product_fx_price_service._upsert_price_item_no_commit",
		lambda *a, **k: fake_upsert(**k),
	)

	# db.get(PriceList) and Business
	def get_side(model, pk):
		name = getattr(model, "__name__", str(model))
		if "PriceList" in name:
			return pl
		if "Business" in name:
			return biz
		return None

	db.get.side_effect = get_side

	res = sync_price_list_from_product_base(db, product)
	assert res["synced"] is True
	assert res["price_list_id"] == 3
	assert calls["currency_id"] == 1
	assert calls["price"] == Decimal("6000000")
	assert calls["product_id"] == 10
