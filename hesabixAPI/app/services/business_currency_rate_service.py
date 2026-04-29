from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import and_, desc, func, select
from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.business_currency_rate import BusinessCurrencyRate
from adapters.db.models.currency import BusinessCurrency, Currency
from app.core.responses import ApiError


def _to_utc_aware(dt: datetime) -> datetime:
	if dt.tzinfo is None:
		return dt.replace(tzinfo=timezone.utc)
	return dt.astimezone(timezone.utc)


def _get_business_default_currency_id(db: Session, business_id: int) -> int:
	b = db.get(Business, int(business_id))
	if not b:
		raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)
	if b.default_currency_id is None:
		raise ApiError("BUSINESS_CURRENCY", "ارز اصلی کسب‌وکار تعریف نشده است", http_status=400)
	return int(b.default_currency_id)


def _is_currency_secondary_for_business(
	db: Session, business_id: int, currency_id: int, default_currency_id: int
) -> bool:
	"""فقط ارزهای غیرپایه‌ای که در business_currencies فعال‌اند (نه ارز اصلی)."""
	if int(currency_id) == int(default_currency_id):
		return False
	q = select(BusinessCurrency.id).where(
		and_(
			BusinessCurrency.business_id == int(business_id),
			BusinessCurrency.currency_id == int(currency_id),
		)
	).limit(1)
	return db.execute(q).scalar_one_or_none() is not None


def assert_currency_allows_rate(db: Session, business_id: int, currency_id: int) -> None:
	dcid = _get_business_default_currency_id(db, business_id)
	if int(currency_id) == int(dcid):
		raise ApiError("CURRENCY_IS_BASE", "برای ارز اصلی کسب‌وکار نرخ تسعیر ثبت نمی‌شود (همیشه ۱)", http_status=400)
	if not _is_currency_secondary_for_business(db, business_id, int(currency_id), dcid):
		raise ApiError("CURRENCY_NOT_ALLOWED", "این ارز برای این کسب‌وکار فعال نیست", http_status=400)


def _row_to_dict(db: Session, row: BusinessCurrencyRate) -> Dict[str, Any]:
	cur = row.currency
	if cur is None:
		cur = db.get(Currency, row.currency_id)
	return {
		"id": row.id,
		"business_id": row.business_id,
		"currency_id": row.currency_id,
		"currency": {
			"id": cur.id,
			"code": cur.code,
			"title": cur.title,
			"symbol": cur.symbol,
		}
		if cur
		else None,
		"effective_at": row.effective_at,
		"rate": row.rate,
		"note": row.note,
		"created_by_user_id": row.created_by_user_id,
	}


def list_business_currency_rates(
	db: Session,
	business_id: int,
	*,
	currency_id: Optional[int] = None,
	skip: int = 0,
	take: int = 50,
) -> Tuple[List[Dict[str, Any]], int]:
	_ = _get_business_default_currency_id(db, business_id)
	wheres = [BusinessCurrencyRate.business_id == int(business_id)]
	if currency_id is not None:
		wheres.append(BusinessCurrencyRate.currency_id == int(currency_id))
	total = int(
		db.execute(select(func.count()).select_from(BusinessCurrencyRate).where(*wheres)).scalar() or 0
	)
	q = (
		select(BusinessCurrencyRate)
		.where(*wheres)
		.order_by(desc(BusinessCurrencyRate.effective_at), desc(BusinessCurrencyRate.id))
		.offset(max(0, int(skip)))
		.limit(min(200, max(1, int(take))))
	)
	rows = db.execute(q).scalars().all()
	return [_row_to_dict(db, r) for r in rows], total


def get_by_id_for_business(db: Session, business_id: int, rate_id: int) -> BusinessCurrencyRate:
	row = db.get(BusinessCurrencyRate, int(rate_id))
	if not row or int(row.business_id) != int(business_id):
		raise ApiError("NOT_FOUND", "نرخ یافت نشد", http_status=404)
	return row


def create_business_currency_rate(
	db: Session, business_id: int, user_id: int, data: Dict[str, Any]
) -> Dict[str, Any]:
	currency_id = data.get("currency_id")
	if currency_id is None:
		raise ApiError("CURRENCY_ID_REQUIRED", "currency_id الزامی است", http_status=400)
	assert_currency_allows_rate(db, business_id, int(currency_id))
	raw_effective = data.get("effective_at")
	if raw_effective is None:
		raise ApiError("EFFECTIVE_AT_REQUIRED", "زمان مؤثر الزامی است", http_status=400)
	if isinstance(raw_effective, str):
		# fromisoformat handles Z
		s = raw_effective.replace("Z", "+00:00")
		effective_at = datetime.fromisoformat(s)
	else:
		effective_at = raw_effective
	if not isinstance(effective_at, datetime):
		raise ApiError("EFFECTIVE_AT_INVALID", "زمان مؤثر نامعتبر است", http_status=400)
	effective_at = _to_utc_aware(effective_at)
	rate = data.get("rate")
	if rate is None:
		raise ApiError("RATE_REQUIRED", "نرخ الزامی است", http_status=400)
	rate_dec = Decimal(str(rate))
	if rate_dec <= 0:
		raise ApiError("RATE_INVALID", "نرخ باید بزرگ‌تر از صفر باشد", http_status=400)
	now = datetime.now(timezone.utc)
	note = data.get("note")
	row = BusinessCurrencyRate(
		business_id=int(business_id),
		currency_id=int(currency_id),
		effective_at=effective_at,
		rate=rate_dec,
		note=(str(note) if note is not None and str(note).strip() != "" else None),
		created_by_user_id=int(user_id),
		created_at=now,
		updated_at=now,
	)
	db.add(row)
	db.flush()
	db.refresh(row)
	return _row_to_dict(db, row)


def update_business_currency_rate(
	db: Session, business_id: int, user_id: int, rate_id: int, data: Dict[str, Any]
) -> Dict[str, Any]:
	row = get_by_id_for_business(db, business_id, rate_id)
	# اجازه تغییر currency به ارز معتبر دیگر
	if "currency_id" in data and data["currency_id"] is not None:
		assert_currency_allows_rate(db, business_id, int(data["currency_id"]))
		row.currency_id = int(data["currency_id"])
	if "effective_at" in data and data["effective_at"] is not None:
		raw = data["effective_at"]
		if isinstance(raw, str):
			s = raw.replace("Z", "+00:00")
			eff = datetime.fromisoformat(s)
		else:
			eff = raw
		if not isinstance(eff, datetime):
			raise ApiError("EFFECTIVE_AT_INVALID", "زمان مؤثر نامعتبر است", http_status=400)
		row.effective_at = _to_utc_aware(eff)
	if "rate" in data and data["rate"] is not None:
		r = Decimal(str(data["rate"]))
		if r <= 0:
			raise ApiError("RATE_INVALID", "نرخ باید بزرگ‌تر از صفر باشد", http_status=400)
		row.rate = r
	if "note" in data:
		n = data.get("note")
		row.note = (str(n) if n is not None and str(n).strip() != "" else None)
	row.updated_at = datetime.now(timezone.utc)
	db.flush()
	db.refresh(row)
	return _row_to_dict(db, row)


def delete_business_currency_rate(db: Session, business_id: int, rate_id: int) -> None:
	row = get_by_id_for_business(db, business_id, rate_id)
	db.delete(row)


def resolve_rate_to_base(
	db: Session, business_id: int, currency_id: int, as_of: datetime
) -> Dict[str, Any]:
	"""نرخ تبدیل ۱ واحد `currency_id` به واحد ارز پایه، در لحظه as_of (آخرین نرخ با effective_at <= as_of)."""
	b = db.get(Business, int(business_id))
	if not b:
		raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)
	if b.default_currency_id is None:
		raise ApiError("BUSINESS_CURRENCY", "ارز اصلی کسب‌وکار تعریف نشده است", http_status=400)
	dcid = int(b.default_currency_id)
	as_of_utc = _to_utc_aware(as_of)
	if int(currency_id) == dcid:
		return {
			"base_currency_id": dcid,
			"currency_id": dcid,
			"rate": Decimal(1),
			"effective_at": as_of_utc,
			"rate_row_id": None,
		}
	assert_currency_allows_rate(db, business_id, int(currency_id))
	q = (
		select(BusinessCurrencyRate)
		.where(
			and_(
				BusinessCurrencyRate.business_id == int(business_id),
				BusinessCurrencyRate.currency_id == int(currency_id),
				BusinessCurrencyRate.effective_at <= as_of_utc,
			)
		)
		.order_by(desc(BusinessCurrencyRate.effective_at), desc(BusinessCurrencyRate.id))
		.limit(1)
	)
	row = db.execute(q).scalar_one_or_none()
	if not row:
		raise ApiError("RATE_NOT_FOUND", "نرخی برای این ارز و زمان یافت نشد", http_status=404)
	return {
		"base_currency_id": dcid,
		"currency_id": int(currency_id),
		"rate": row.rate,
		"effective_at": row.effective_at,
		"rate_row_id": row.id,
	}


def resolve_rate_to_base_or_one(
	db: Session, business_id: int, currency_id: int, as_of: datetime
) -> Decimal:
	"""
	مثل resolve_rate_to_base اما در صورت نبود نرخ، خطای ارز غیرمجاز، یا نبود ارز اصلی → ۱ (تسعیر یک‌به‌یک).
	برای داشبورد و تجمیع‌های غیرحساس که نباید خطا دهند.
	"""
	try:
		res = resolve_rate_to_base(db, business_id, int(currency_id), as_of)
		r = res.get("rate")
		return r if isinstance(r, Decimal) else Decimal(str(r))
	except Exception:
		return Decimal(1)
