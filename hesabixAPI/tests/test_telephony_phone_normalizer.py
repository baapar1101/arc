"""Unit tests for Iranian phone normalizer."""
from app.services.telephony.phone_normalizer import normalize_iran_phone, numbers_match


def test_mobile_variants():
	cases = [
		"09121234567",
		"9121234567",
		"989121234567",
		"+989121234567",
		"00989121234567",
		"0912 123 4567",
		"۰۹۱۲۱۲۳۴۵۶۷",
	]
	for raw in cases:
		out = normalize_iran_phone(raw)
		assert out["canonical"] == "09121234567", raw
		assert "09121234567" in out["candidates"]
		assert "989121234567" in out["candidates"]


def test_numbers_match_across_formats():
	assert numbers_match("09121234567", "+989121234567")
	assert numbers_match("02191001234", "2191001234")


def test_short_extension():
	out = normalize_iran_phone("102")
	assert out["canonical"] == "102"
	assert numbers_match("102", "102")
