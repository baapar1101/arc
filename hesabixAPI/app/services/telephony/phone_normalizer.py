"""نرمال‌سازی شماره تلفن ایران برای تطبیق Caller ID."""
from __future__ import annotations

import re
from typing import Iterable, List, Optional, Set

_PERSIAN_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "0123456789" * 2)


def _to_latin_digits(value: str) -> str:
	return value.translate(_PERSIAN_DIGITS)


def extract_digits(raw: str) -> str:
	s = _to_latin_digits(raw or "")
	return re.sub(r"\D+", "", s)


def normalize_iran_phone(raw: Optional[str]) -> dict:
	"""
	خروجی:
	- canonical: فرم ترجیحی ذخیره (موبایل با 0، شهری با 0 در صورت امکان)
	- candidates: لیست فرم‌های قابل جستجو
	"""
	if not raw:
		return {"canonical": None, "candidates": []}

	text = _to_latin_digits(str(raw)).strip()
	has_plus = text.startswith("+")
	digits = extract_digits(text)
	if not digits:
		return {"canonical": None, "candidates": []}

	# حذف پیش‌شماره بین‌المللی تکراری
	if digits.startswith("0098"):
		digits = digits[4:]
		has_plus = True
	elif digits.startswith("98") and len(digits) >= 12:
		digits = digits[2:]
		has_plus = True

	candidates: Set[str] = set()
	canonical: Optional[str] = None

	# موبایل ایران: 10 رقم بعد از حذف 0 / 98 → معمولاً 9xxxxxxxxx
	mobile_body: Optional[str] = None
	if len(digits) == 11 and digits.startswith("09"):
		mobile_body = digits[1:]
	elif len(digits) == 10 and digits.startswith("9"):
		mobile_body = digits
	elif len(digits) == 12 and digits.startswith("989"):
		mobile_body = digits[2:]
	elif has_plus and len(digits) == 10 and digits.startswith("9"):
		mobile_body = digits

	if mobile_body and len(mobile_body) == 10 and mobile_body.startswith("9"):
		local = "0" + mobile_body
		e164_digits = "98" + mobile_body
		candidates.update({local, mobile_body, e164_digits, "+" + e164_digits, "00" + e164_digits})
		canonical = local
	else:
		# شهری / سایر
		if len(digits) >= 8:
			if not digits.startswith("0") and len(digits) in (8, 10, 11):
				# اگر با کد شهر بدون صفر آمده
				with_zero = "0" + digits
				candidates.add(with_zero)
				candidates.add(digits)
				if len(digits) >= 10:
					candidates.add("98" + digits.lstrip("0"))
				canonical = with_zero if len(with_zero) <= 12 else digits
			else:
				candidates.add(digits)
				if digits.startswith("0"):
					stripped = digits.lstrip("0")
					candidates.add(stripped)
					candidates.add("98" + stripped)
					candidates.add("+98" + stripped)
				canonical = digits
		else:
			# داخلی کوتاه و غیره
			candidates.add(digits)
			canonical = digits

	# همیشه فرم خام ارقام هم نگه داشته شود
	candidates.add(extract_digits(text))
	ordered = _stable_unique([c for c in [canonical, *sorted(candidates, key=len, reverse=True)] if c])
	return {"canonical": canonical, "candidates": ordered}


def _stable_unique(items: Iterable[str]) -> List[str]:
	seen: Set[str] = set()
	out: List[str] = []
	for item in items:
		if item and item not in seen:
			seen.add(item)
			out.append(item)
	return out


def numbers_match(a: Optional[str], b: Optional[str], min_len: int = 8) -> bool:
	na = normalize_iran_phone(a)
	nb = normalize_iran_phone(b)
	if not na["candidates"] or not nb["candidates"]:
		return False
	set_a = {c for c in na["candidates"] if len(extract_digits(c)) >= min_len or len(c) < min_len}
	set_b = set(nb["candidates"])
	# برای داخلی‌های کوتاه، تطبیق دقیق
	if len(extract_digits(a or "")) < min_len or len(extract_digits(b or "")) < min_len:
		return bool(set_a & set_b)
	return bool(set_a & set_b)
