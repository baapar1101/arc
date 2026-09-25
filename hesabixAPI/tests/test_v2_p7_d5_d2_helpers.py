"""V2-P7 D5/D2 + V2-P8 health helpers."""
from __future__ import annotations

from decimal import Decimal

from app.services.fx_rate_provider_service import (
	_map_raw_items_to_currency_shape,
	extract_currency_items_from_provider_payload,
)
from app.services.invoice_fx_revaluation import (
	apply_rate_display_unit,
	display_rate_factor_for_unit,
)


def test_mesghal_tala_like_payload_extract():
	payload = {
		"success": True,
		"rates": [
			{"key": "usd", "title": "دلار", "value": 140000, "currency": "IRT"},
			{"key": "eur", "title": "یورو", "value": 165000, "currency": "IRT"},
			{"key": "gold18", "title": "طلا", "value": 7000000, "currency": "IRT"},
		],
	}
	cfg = {
		"items_path": "rates",
		"item_symbol_field": "key",
		"item_price_field": "value",
		"item_name_field": "title",
		"item_unit_field": "currency",
		"quote_unit": "IRT",
	}
	items = extract_currency_items_from_provider_payload(payload, cfg)
	assert len(items) == 3
	assert items[0]["symbol"] == "USD"
	assert items[0]["price"] == 140000


def test_brs_native_items_pass_through():
	raw = [{"symbol": "USD", "price": 140000, "unit": "تومان"}]
	mapped = _map_raw_items_to_currency_shape(raw, {"item_symbol_field": "symbol", "item_price_field": "price"})
	assert mapped[0]["symbol"] == "USD"


def test_d2_display_rate_irr_to_toman():
	assert display_rate_factor_for_unit(base_currency_code="IRR", display_unit="toman") == Decimal("0.1")
	assert apply_rate_display_unit(1400000, base_currency_code="IRR", display_unit="toman") == Decimal("140000")
	assert display_rate_factor_for_unit(base_currency_code="IRT", display_unit="irr") == Decimal(10)
	assert display_rate_factor_for_unit(base_currency_code="IRR", display_unit="as_base") == Decimal(1)
