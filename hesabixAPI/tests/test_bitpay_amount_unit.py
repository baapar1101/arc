from app.services.payment_service import (
	_BITPAY_WIRE_MAX,
	_BITPAY_WIRE_MIN,
	_bitpay_amount_unit,
	_bitpay_wire_amount,
)


def test_bitpay_defaults_to_toman_wire_amount() -> None:
	cfg: dict = {}
	assert _bitpay_amount_unit(cfg) == "toman"
	assert _bitpay_wire_amount(121_000_000, cfg) == 12_100_000


def test_bitpay_rial_mode_keeps_amount() -> None:
	cfg = {"amount_unit": "rial"}
	assert _bitpay_amount_unit(cfg) == "rial"
	assert _bitpay_wire_amount(121_000_000, cfg) == 121_000_000


def test_bitpay_currency_alias_r() -> None:
	cfg = {"currency": "R"}
	assert _bitpay_amount_unit(cfg) == "rial"


def test_bitpay_wire_limits() -> None:
	assert _BITPAY_WIRE_MIN["toman"] == 5000
	assert _BITPAY_WIRE_MIN["rial"] == 50_000
	assert _BITPAY_WIRE_MAX["toman"] == 50_000_000
	assert _BITPAY_WIRE_MAX["rial"] == 500_000_000
