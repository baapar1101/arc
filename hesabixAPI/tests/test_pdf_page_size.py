from __future__ import annotations

from app.services.pdf.page_size import (
	build_page_size_css,
	canonical_receipt_width,
	is_receipt_paper,
	receipt_page_chrome_css,
)


def test_canonical_receipt_width_aliases():
	assert canonical_receipt_width("60mm") == "60mm"
	assert canonical_receipt_width("6cm") == "60mm"
	assert canonical_receipt_width("80mm") == "80mm"
	assert canonical_receipt_width("8cm") == "80mm"
	assert canonical_receipt_width("100mm") == "100mm"
	assert canonical_receipt_width("10cm") == "100mm"
	assert canonical_receipt_width("80mm 297mm") == "80mm"
	assert canonical_receipt_width("A4") is None
	assert canonical_receipt_width(None) is None


def test_build_page_size_css_receipt_skips_orientation():
	assert build_page_size_css("80mm", "landscape") == "80mm 297mm"
	assert build_page_size_css("60mm", "portrait") == "60mm 297mm"
	assert build_page_size_css("100mm", None) == "100mm 297mm"


def test_build_page_size_css_named_keeps_orientation():
	assert build_page_size_css("A4", "landscape") == "A4 landscape"
	assert build_page_size_css(None, None) == "A4 portrait"


def test_build_page_size_css_custom_mm_pair():
	assert build_page_size_css("105mm 148mm", "landscape") == "105mm 148mm"


def test_is_receipt_paper():
	assert is_receipt_paper("80mm") is True
	assert is_receipt_paper("A5") is False


def test_receipt_chrome_hides_page_numbers():
	css = receipt_page_chrome_css()
	assert "content: none" in css
	assert "@page :first" in css
