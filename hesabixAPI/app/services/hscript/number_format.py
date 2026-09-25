"""قالب‌بندی اعداد برای HScript (جداکننده هزارگان، اعشار، درصد، ارز)."""

from __future__ import annotations

import re
from decimal import Decimal, InvalidOperation
from typing import Any, Optional

from app.services.hscript.errors import TypeErrorHS

# نام‌های مجاز format
_ALIASES: dict[str, str] = {
	"number": "number",
	"num": "number",
	"n": "number",
	"integer": "integer",
	"int": "integer",
	"currency": "currency",
	"money": "currency",
	"rial": "currency",
	"toman": "currency",
	"percent": "percent",
	"pct": "percent",
	"%": "percent",
	"decimal": "decimal",
	"float": "decimal",
	"raw": "raw",
	"plain": "raw",
}


def parse_format_spec(fmt: Any) -> tuple[str, Optional[int]]:
	"""
	پارس مشخصه قالب:
	- "currency"
	- "number:2"
	- "decimal:3"
	- "percent:1"
	"""
	if fmt is None:
		return "raw", None
	s = str(fmt).strip().lower()
	if not s:
		return "raw", None
	decimals: Optional[int] = None
	if ":" in s:
		base, dec = s.split(":", 1)
		s = base.strip()
		try:
			decimals = max(0, min(8, int(dec.strip())))
		except ValueError as exc:
			raise TypeErrorHS("تعداد اعشار format نامعتبر است") from exc
	kind = _ALIASES.get(s)
	if not kind:
		raise TypeErrorHS(
			f"قالب عدد نامعتبر: {fmt}. مجاز: number, currency, percent, integer, decimal, raw"
		)
	return kind, decimals


def _to_decimal(value: Any) -> Optional[Decimal]:
	if value is None or isinstance(value, bool):
		return None
	if isinstance(value, Decimal):
		return value
	if isinstance(value, int):
		return Decimal(value)
	if isinstance(value, float):
		return Decimal(str(value))
	s = str(value).strip()
	if not s:
		return None
	# حذف جداکننده‌های رایج قبل از parse
	s = s.replace(",", "").replace("٬", "").replace(" ", "").replace("٪", "")
	s = s.rstrip("%")
	try:
		return Decimal(s)
	except (InvalidOperation, ValueError):
		return None


def format_number(
	value: Any,
	fmt: Any = "number",
	*,
	thousands_sep: str = ",",
	decimal_sep: str = ".",
	default_currency_decimals: int = 0,
	default_number_decimals: int = 0,
	default_percent_decimals: int = 1,
) -> str:
	"""
	قالب‌بندی عدد برای نمایش.

	Examples:
	  format_number(1234567, "currency") -> "1,234,567"
	  format_number(12.5, "percent") -> "12.5%"
	  format_number(1234.567, "number:2") -> "1,234.57"
	"""
	if value is None:
		return "—"
	kind, decimals = parse_format_spec(fmt)
	if kind == "raw":
		return str(value)

	num = _to_decimal(value)
	if num is None:
		return str(value)

	if kind == "integer":
		decimals = 0
	elif kind == "currency":
		if decimals is None:
			decimals = default_currency_decimals
	elif kind == "percent":
		if decimals is None:
			decimals = default_percent_decimals
	elif kind == "decimal":
		if decimals is None:
			decimals = 2
	else:  # number
		if decimals is None:
			# اگر خود عدد اعشار دارد و کاربر نگفته، تا ۲ نگه دار
			if num == num.to_integral_value():
				decimals = default_number_decimals
			else:
				decimals = min(2, abs(num.as_tuple().exponent))

	q = Decimal(10) ** -int(decimals)
	rounded = num.quantize(q)
	sign = "-" if rounded < 0 else ""
	rounded = abs(rounded)
	s = f"{rounded:.{int(decimals)}f}"
	int_part, _, frac = s.partition(".")
	# جداکننده هزارگان
	sep = str(thousands_sep)[:2] if thousands_sep is not None else ""
	if sep:
		int_part = re.sub(r"\B(?=(\d{3})+(?!\d))", sep, int_part)
	dec = str(decimal_sep)[:2] if decimal_sep else "."
	out = f"{sign}{int_part}"
	if decimals and frac:
		out = f"{out}{dec}{frac}"
	if kind == "percent":
		out = f"{out}%"
	return out


def normalize_number_format_options(options: dict[str, Any] | None) -> dict[str, Any]:
	"""گزینه‌های پیش‌فرض قالب عدد برای meta گزارش."""
	opts = dict(options or {})
	sep = str(opts.get("thousands_sep", ",") or ",")[:2]
	dec = str(opts.get("decimal_sep", ".") or ".")[:2]
	style = str(opts.get("style", "western") or "western").lower()
	if style in ("fa", "persian", "iran"):
		# ارقام لاتین + جداکننده فارسی متداول
		sep = "٬"
		dec = "٫"
	return {
		"thousands_sep": sep,
		"decimal_sep": dec,
		"style": "fa" if style in ("fa", "persian", "iran") else "western",
	}
