"""نرمال‌سازی CSS ``@page size`` برای PDF (WeasyPrint).

سایزهای فیش پرینتر عرض ثابت دارند و ارتفاع هر تکهٔ PDF برابر
``RECEIPT_PAGE_HEIGHT`` است تا محتوا روی رول چندصفحه شود.
"""
from __future__ import annotations

from typing import Any, Dict, Optional

RECEIPT_PAGE_HEIGHT = "297mm"
RECEIPT_MODULE_KEY = "invoices"
RECEIPT_SUBTYPE = "receipt"

# توکن UI/API → عرض استاندارد
_RECEIPT_WIDTH_ALIASES: Dict[str, str] = {
	"60mm": "60mm",
	"80mm": "80mm",
	"100mm": "100mm",
	"6cm": "60mm",
	"8cm": "80mm",
	"10cm": "100mm",
}

RECEIPT_PAPER_SIZES = frozenset(_RECEIPT_WIDTH_ALIASES.keys())

RECEIPT_DEFAULT_MARGINS_MM: Dict[str, float] = {
	"top": 3,
	"right": 2,
	"bottom": 4,
	"left": 2,
}


def _norm_token(value: Optional[str]) -> str:
	return (value or "").strip().lower().replace(" ", "")


def canonical_receipt_width(paper_size: Optional[str]) -> Optional[str]:
	"""اگر سایز فیش باشد عرض استاندارد (مثلاً ``80mm``) برمی‌گرداند."""
	ps = (paper_size or "").strip()
	if not ps:
		return None
	compact = _norm_token(ps)
	direct = _RECEIPT_WIDTH_ALIASES.get(compact) or _RECEIPT_WIDTH_ALIASES.get(ps)
	if direct:
		return direct
	first = ps.split()[0] if ps.split() else ""
	mapped = _RECEIPT_WIDTH_ALIASES.get(_norm_token(first)) or _RECEIPT_WIDTH_ALIASES.get(first)
	if mapped:
		# «80mm 297mm» یا «80mm297mm»
		rest = compact[len(_norm_token(mapped)) :]
		if rest in ("", "297mm", "x297mm"):
			return mapped
	return None


def is_receipt_paper(paper_size: Optional[str]) -> bool:
	return canonical_receipt_width(paper_size) is not None


def build_page_size_css(paper_size: Optional[str], orientation: Optional[str]) -> str:
	"""رشتهٔ معتبر برای ``@page { size: … }``.

	- فیش: ``80mm 297mm`` بدون کلید orientation
	- دو مقدار mm سفارشی: همان رشته، بدون orientation
	- نام استاندارد: ``A4 landscape``
	"""
	ps = (paper_size or "A4").strip() or "A4"
	ori = (orientation or "portrait").strip().lower()
	if ori not in ("portrait", "landscape"):
		ori = "portrait"
	width = canonical_receipt_width(ps)
	if width:
		return f"{width} {RECEIPT_PAGE_HEIGHT}"
	if "mm" in ps.lower() and ps.lower().count("mm") >= 2:
		return ps
	return f"{ps} {ori}"


def receipt_page_chrome_css(*, continuation_label: str = "ادامه فاکتور") -> str:
	"""شماره صفحه را برای فیش خاموش می‌کند و سربرگ ادامه روی صفحات بعد می‌گذارد."""
	label = (continuation_label or "").replace("\\", "").replace('"', "'")
	return (
		"@page {"
		" @bottom-left { content: none; }"
		" @bottom-right { content: none; }"
		f' @top-center {{ content: "{label}"; font-size: 7px; color: #888; }}'
		" }"
		"@page :first { @top-center { content: none; } }"
	)


def default_receipt_margins() -> Dict[str, Any]:
	return dict(RECEIPT_DEFAULT_MARGINS_MM)
