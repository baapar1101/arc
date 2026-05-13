"""تبدیل واحد پول باسلام ↔ ریال داخلی."""

from __future__ import annotations

from app.services import basalam_integration_service as bas


def test_incoming_toman_multiplies_by_ten() -> None:
    s = {"basalam_monetary_unit": "toman"}
    assert bas._incoming_basalam_amount_to_rial_amount(15000, s) == 150000.0


def test_incoming_rial_no_change() -> None:
    s = {"basalam_monetary_unit": "rial"}
    assert bas._incoming_basalam_amount_to_rial_amount(150000, s) == 150000.0


def test_outbound_toman_divides_by_ten() -> None:
    s = {"basalam_monetary_unit": "toman"}
    assert bas._internal_rial_amount_to_basalam_wire(150000, s) == 15000.0


def test_normalize_monetary_unit_typo_defaults_to_rial() -> None:
    prev = bas._default_settings()
    out = bas._normalize_settings({"basalam_monetary_unit": "unknown"}, prev)
    assert out["basalam_monetary_unit"] == "rial"


def test_normalize_monetary_unit_persian_label() -> None:
    prev = bas._default_settings()
    out = bas._normalize_settings({"basalam_monetary_unit": "تومان"}, prev)
    assert out["basalam_monetary_unit"] == "toman"
