"""تست‌های سبک سرویس قیمت ارزی کالا و تسعیر پایان دوره."""
from decimal import Decimal

from app.services.product_fx_price_service import apply_fx_prices_to_base_for_product


class _FakeProduct:
	def __init__(self):
		self.id = 1
		self.business_id = 1
		self.auto_update_base_from_fx = True
		self.price_fx_currency_id = 2
		self.sales_price_fx = Decimal("100")
		self.purchase_price_fx = Decimal("80")
		self.base_sales_price = Decimal("0")
		self.base_purchase_price = Decimal("0")


def test_apply_fx_prices_disabled_without_auto_flag(monkeypatch):
	p = _FakeProduct()
	p.auto_update_base_from_fx = False
	res = apply_fx_prices_to_base_for_product(None, p, force=False)  # type: ignore[arg-type]
	assert res["updated"] is False
	assert res["reason"] == "auto_update_disabled"


def test_period_end_preview_importable():
	from app.services.period_end_fx_revaluation_service import preview_period_end_fx_revaluation

	assert callable(preview_period_end_fx_revaluation)
