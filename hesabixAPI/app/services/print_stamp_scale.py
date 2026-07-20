"""مقیاس مهر و امضا در خروجی PDF چاپ اسناد.

اندازهٔ پایه (۱۰۰٪) همان مقادیر ثابت قبلی قالب‌هاست؛ مقیاس فقط هنگام رندر اعمال می‌شود.
"""

from __future__ import annotations

from typing import Any, Mapping, Optional

STAMP_SCALE_MIN = 50
STAMP_SCALE_MAX = 200
STAMP_SCALE_DEFAULT = 100

# اندازهٔ پایه فاکتور (CSS قبلی: فقط max-width)
INVOICE_STAMP_BASE_MAX_WIDTH_PX = 160
INVOICE_SIGNATURE_BASE_MAX_WIDTH_PX = 140

# اندازهٔ پایه رسید/پرداخت و انتقال
RECEIPT_STAMP_BASE_MAX_HEIGHT_PX = 60
RECEIPT_STAMP_BASE_MAX_WIDTH_PX = 140
RECEIPT_SIGNATURE_BASE_MAX_HEIGHT_PX = 40
RECEIPT_SIGNATURE_BASE_MAX_WIDTH_PX = 140


def clamp_scale_percent(value: Any, default: int = STAMP_SCALE_DEFAULT) -> int:
	"""نرمال‌سازی و محدود کردن درصد مقیاس به بازهٔ مجاز."""
	if value is None:
		return int(default)
	try:
		if isinstance(value, bool):
			return int(default)
		if isinstance(value, str):
			s = value.strip()
			if not s:
				return int(default)
			n = int(float(s))
		elif isinstance(value, (int, float)):
			n = int(round(float(value)))
		else:
			return int(default)
	except (TypeError, ValueError):
		return int(default)
	if n < STAMP_SCALE_MIN:
		return STAMP_SCALE_MIN
	if n > STAMP_SCALE_MAX:
		return STAMP_SCALE_MAX
	return n


def scaled_px(base_px: int, scale_percent: int) -> int:
	"""محاسبه پیکسل نهایی با حفظ حداقل ۱px."""
	pct = clamp_scale_percent(scale_percent)
	return max(1, int(round(base_px * pct / 100.0)))


def extract_scales_from_settings(
	settings: Optional[Mapping[str, Any]],
) -> tuple[int, int]:
	"""خواندن مقیاس مهر و امضا از dict تنظیمات چاپ."""
	src = settings or {}
	stamp = clamp_scale_percent(
		src.get("stamp_scale_percent"), STAMP_SCALE_DEFAULT
	)
	signature = clamp_scale_percent(
		src.get("signature_scale_percent"), STAMP_SCALE_DEFAULT
	)
	return stamp, signature


def invoice_stamp_signature_sizes(
	stamp_scale_percent: int = STAMP_SCALE_DEFAULT,
	signature_scale_percent: int = STAMP_SCALE_DEFAULT,
) -> dict[str, int]:
	"""ابعاد نهایی مهر/امضا برای قالب PDF فاکتور."""
	stamp_pct = clamp_scale_percent(stamp_scale_percent)
	sig_pct = clamp_scale_percent(signature_scale_percent)
	return {
		"stamp_scale_percent": stamp_pct,
		"signature_scale_percent": sig_pct,
		"stamp_max_width_px": scaled_px(INVOICE_STAMP_BASE_MAX_WIDTH_PX, stamp_pct),
		"signature_max_width_px": scaled_px(
			INVOICE_SIGNATURE_BASE_MAX_WIDTH_PX, sig_pct
		),
	}


def receipt_stamp_signature_sizes(
	stamp_scale_percent: int = STAMP_SCALE_DEFAULT,
	signature_scale_percent: int = STAMP_SCALE_DEFAULT,
) -> dict[str, int]:
	"""ابعاد نهایی مهر/امضا برای قالب PDF رسید/پرداخت و انتقال."""
	stamp_pct = clamp_scale_percent(stamp_scale_percent)
	sig_pct = clamp_scale_percent(signature_scale_percent)
	return {
		"stamp_scale_percent": stamp_pct,
		"signature_scale_percent": sig_pct,
		"stamp_max_width_px": scaled_px(RECEIPT_STAMP_BASE_MAX_WIDTH_PX, stamp_pct),
		"stamp_max_height_px": scaled_px(RECEIPT_STAMP_BASE_MAX_HEIGHT_PX, stamp_pct),
		"signature_max_width_px": scaled_px(
			RECEIPT_SIGNATURE_BASE_MAX_WIDTH_PX, sig_pct
		),
		"signature_max_height_px": scaled_px(
			RECEIPT_SIGNATURE_BASE_MAX_HEIGHT_PX, sig_pct
		),
	}
