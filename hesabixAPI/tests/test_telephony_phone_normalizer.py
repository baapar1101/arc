"""Unit tests for Iranian phone normalizer."""
import pytest

from app.services.telephony.phone_normalizer import (
	identity_candidates,
	normalize_iran_phone,
	numbers_match,
)


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


def test_identity_candidates_ir_mobile_includes_e164():
	pytest.importorskip("phonenumbers")
	out = identity_candidates("09121234567", default_region="IR")
	assert out["e164"] == "+989121234567"
	assert "09121234567" in out["candidates"]
	assert "+989121234567" in out["candidates"]
	assert not out["is_short"]


def test_identity_candidates_extension_is_short():
	out = identity_candidates("102", default_region="IR")
	assert out["is_short"]
	assert out["e164"] is None
	assert "102" in out["candidates"]
