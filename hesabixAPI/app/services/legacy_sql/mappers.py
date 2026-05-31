from __future__ import annotations

import re
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from typing import Any, Dict, List, Optional, Tuple

from adapters.db.models.business import BusinessField, BusinessType


def normalize_email(email: str | None) -> str | None:
	return email.lower().strip() if email else None


def split_full_name(full_name: Optional[str]) -> Tuple[Optional[str], Optional[str]]:
	if not full_name or not str(full_name).strip():
		return None, None
	parts = str(full_name).strip().split()
	if len(parts) == 1:
		return parts[0], None
	return parts[0], " ".join(parts[1:])


def convert_timestamp_to_datetime(timestamp_str: str | None) -> datetime:
	if not timestamp_str:
		return datetime.utcnow()
	try:
		s = str(timestamp_str).strip()
		if s.isdigit():
			return datetime.fromtimestamp(int(s))
		return datetime.fromisoformat(s.replace("Z", "+00:00"))
	except Exception:
		return datetime.utcnow()


def convert_persian_date_to_date(date_str: str | None) -> date | None:
	if not date_str or not str(date_str).strip():
		return None
	date_str = str(date_str).strip()
	match = re.match(r"^(\d{4})/(\d{1,2})/(\d{1,2})$", date_str)
	if match:
		year, month, day = match.groups()
		try:
			import jdatetime

			jd = jdatetime.date(int(year), int(month), int(day))
			return jd.togregorian()
		except ImportError:
			try:
				return date(int(year) + 621, int(month), int(day))
			except (ValueError, TypeError):
				return None
		except Exception:
			return None
	return None


def convert_amount(amount: Any) -> Decimal:
	if amount is None:
		return Decimal(0)
	try:
		cleaned = str(amount).strip().replace(",", "").replace(" ", "").replace("،", "")
		if not cleaned or cleaned == "0":
			return Decimal(0)
		return Decimal(cleaned)
	except (ValueError, InvalidOperation, TypeError):
		return Decimal(0)


def map_business_type(old_type: str | None) -> BusinessType:
	if not old_type:
		return BusinessType.STORE
	mapping = {
		"فروشگاه": BusinessType.STORE,
		"مغازه": BusinessType.SHOP,
		"شرکت": BusinessType.COMPANY,
		"شخصی": BusinessType.INDIVIDUAL,
		"موسسه": BusinessType.INSTITUTE,
		"باشگاه": BusinessType.CLUB,
		"اتحادیه": BusinessType.UNION,
	}
	return mapping.get(str(old_type).strip(), BusinessType.STORE)


def map_business_field(old_field: str | None) -> BusinessField:
	if not old_field:
		return BusinessField.OTHER
	mapping = {
		"تولیدی": BusinessField.MANUFACTURING,
		"بازرگانی": BusinessField.TRADING,
		"خدماتی": BusinessField.SERVICE,
		"سایر": BusinessField.OTHER,
	}
	return mapping.get(str(old_field).strip(), BusinessField.OTHER)


def unix_ts_to_date(ts: str | None) -> date | None:
	if not ts:
		return None
	try:
		return datetime.fromtimestamp(int(str(ts).strip())).date()
	except Exception:
		return None


INVOICE_TYPE_MAP = {
	"sell": "invoice_sales",
	"buy": "invoice_purchase",
	"rfsell": "invoice_sales_return",
	"rfbuy": "invoice_purchase_return",
}


def is_valid_mapped_id(mapped_id: int | None, *, dry_run: bool = False) -> bool:
	"""شناسه نگاشت‌شده معتبر است (در dry_run شناسه‌های منفی placeholder هم پذیرفته می‌شوند)."""
	if mapped_id is None:
		return False
	if mapped_id > 0:
		return True
	return dry_run and mapped_id < 0


def convert_warehouse_doc_type(old_type: str | None, type_string: str | None = None) -> str:
	"""تبدیل type قدیمی storeroom_ticket به doc_type جدید."""
	if not old_type:
		return "adjustment"
	type_string_lower = (type_string or "").lower()
	if old_type == "input":
		if "انتقال" in type_string_lower:
			return "transfer"
		if "تولید" in type_string_lower:
			return "production_in"
		return "receipt"
	if old_type == "output":
		if "انتقال" in type_string_lower:
			return "transfer"
		if "تولید" in type_string_lower:
			return "production_out"
		return "issue"
	return "adjustment"


def convert_line_quantity(count: Any) -> Decimal:
	try:
		cleaned = str(count or "").strip().replace(",", "")
		if not cleaned:
			return Decimal(0)
		q = Decimal(cleaned)
		return q if q > 0 else Decimal(0)
	except (ValueError, InvalidOperation, TypeError):
		return Decimal(0)
