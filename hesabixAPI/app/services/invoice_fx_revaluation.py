"""
تسعیر ارز روی extra_info سند فاکتور: snap نرخ نسبت به ارز اصلی کسب‌وکار.

سیاست از فیلد businesses.fx_revaluation_policy (و در نبود، پیش‌فرض کد) خوانده می‌شود.
"""
from __future__ import annotations

from datetime import date, datetime, time, timezone
from decimal import Decimal
from typing import Any, Dict, Optional

from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from app.core.responses import ApiError
from app.services.business_currency_rate_service import (
	_to_utc_aware,
	assert_currency_allows_rate,
	get_by_id_for_business,
	resolve_rate_to_base,
)

# کلیدهای مجاز JSON سیاست
DEFAULT_FX_REVALUATION_POLICY: Dict[str, str] = {
	# document_date: از تاریخ سند (با document_date_effective) | registered_at: زمان ثبت سند
	"as_of_source": "document_date",
	# اگر as_of_source=document_date: لحظه مؤثر در همان روز (UTC)
	"document_date_effective": "end_of_day",  # start_of_day | noon | end_of_day
	# block: بدون نرخ ثبت ممنوع | allow_without_fx: بدون بلوک، fx ممکن است ناقص باشد
	"when_no_rate": "block",
}


def get_fx_revaluation_policy(business: Business) -> Dict[str, str]:
	"""ادغام سیاست ذخیره‌شده با پیش‌فرض."""
	raw = getattr(business, "fx_revaluation_policy", None) or {}
	if not isinstance(raw, dict):
		raw = {}
	out = dict(DEFAULT_FX_REVALUATION_POLICY)
	for k, v in raw.items():
		if k in DEFAULT_FX_REVALUATION_POLICY and v is not None and str(v).strip() != "":
			out[k] = str(v).strip()
	try:
		_validate_policy(out)
	except Exception:
		return dict(DEFAULT_FX_REVALUATION_POLICY)
	return out


def _validate_policy(p: Dict[str, str]) -> None:
	if p.get("as_of_source") not in ("document_date", "registered_at"):
		raise ValueError("as_of_source نامعتبر")
	if p.get("document_date_effective") not in ("start_of_day", "noon", "end_of_day"):
		raise ValueError("document_date_effective نامعتبر")
	if p.get("when_no_rate") not in ("block", "allow_without_fx"):
		raise ValueError("when_no_rate نامعتبر")


def validate_and_normalize_fx_revaluation_policy_payload(raw: Any) -> Optional[Dict[str, str]]:
	"""برای API ویرایش کسب‌وکار: اعتبارسنجی و برگرداندن دیکشنار نهایی یا None."""
	if raw is None:
		return None
	if not isinstance(raw, dict):
		raise ValueError("fx_revaluation_policy باید شیء JSON باشد")
	out = dict(DEFAULT_FX_REVALUATION_POLICY)
	for k, v in raw.items():
		if k in DEFAULT_FX_REVALUATION_POLICY and v is not None and str(v).strip() != "":
			out[k] = str(v).strip()
	_validate_policy(out)
	return out


def compute_fx_as_of_utc(
	document_date: date,
	registered_at_utc: datetime,
	policy: Dict[str, str],
) -> datetime:
	"""لحظه as_of طبق سیاست (UTC)."""
	reg = _to_utc_aware(registered_at_utc)
	if policy.get("as_of_source") == "registered_at":
		return reg
	eff = policy.get("document_date_effective") or "end_of_day"
	if eff == "start_of_day":
		tm = time(0, 0, 0)
	elif eff == "noon":
		tm = time(12, 0, 0)
	else:
		tm = time(23, 59, 59, 999999)
	return datetime.combine(document_date, tm, tzinfo=timezone.utc)


def _rate_row_to_fx_dict(
	*,
	base_id: int,
	currency_id: int,
	rate: Decimal,
	effective_at: datetime,
	rate_row_id: Optional[int],
	mode: str,
) -> Dict[str, Any]:
	return {
		"base_currency_id": base_id,
		"document_currency_id": currency_id,
		"rate": str(rate),
		"effective_at": effective_at.isoformat() if effective_at else None,
		"rate_row_id": rate_row_id,
		"mode": mode,  # auto | selected | base
	}


def apply_fx_revaluation_to_invoice_extra(
	db: Session,
	business: Business,
	*,
	document_currency_id: int,
	document_date: date,
	extra_info: Dict[str, Any],
	data: Dict[str, Any],
	user_can_select_fx_rate: bool,
	registered_at_utc: datetime,
) -> Dict[str, Any]:
	"""
	روی نسخه extra_info (شبیه) کار می‌کند و کلید 'fx' را اضافه/به‌روز می‌کند.
	"""
	extra: Dict[str, Any] = dict(extra_info) if extra_info else {}
	business_id = int(business.id)
	base_id = business.default_currency_id
	if not base_id:
		# بدون ارز اصلی، تسعیر معنا ندارد
		extra["fx"] = {
			"skipped": True,
			"reason": "no_default_currency",
		}
		return extra

	if int(document_currency_id) == int(base_id):
		extra["fx"] = _rate_row_to_fx_dict(
			base_id=int(base_id),
			currency_id=int(document_currency_id),
			rate=Decimal(1),
			effective_at=_to_utc_aware(registered_at_utc),
			rate_row_id=None,
			mode="base",
		)
		return extra

	policy = get_fx_revaluation_policy(business)
	as_of = compute_fx_as_of_utc(document_date, registered_at_utc, policy)
	assert_currency_allows_rate(db, business_id, int(document_currency_id))

	fx_rate_id: Optional[int] = None
	if user_can_select_fx_rate and data:
		if data.get("fx_rate_id") is not None:
			try:
				fx_rate_id = int(data["fx_rate_id"])
			except (TypeError, ValueError):
				fx_rate_id = None

	# اگر ارسال شده اما مجوز انتخاب نیست: نادیده بگیر
	if not user_can_select_fx_rate:
		fx_rate_id = None

	if fx_rate_id is not None:
		row = get_by_id_for_business(db, business_id, int(fx_rate_id))
		if int(row.currency_id) != int(document_currency_id):
			raise ApiError("FX_RATE_MISMATCH", "نرخ انتخاب‌شده با ارز سند سازگار نیست", http_status=400)
		if _to_utc_aware(row.effective_at) > as_of:
			raise ApiError(
				"FX_RATE_INVALID",
				"زمان مؤثر نرخ انتخاب‌شده بعد از لحظه مرجع تسعیر سند است",
				http_status=400,
			)
		extra["fx"] = _rate_row_to_fx_dict(
			base_id=int(base_id),
			currency_id=int(document_currency_id),
			rate=row.rate,
			effective_at=row.effective_at,
			rate_row_id=row.id,
			mode="selected",
		)
		return extra

	# خودکار: نزدیک‌ترین نرخ (آخرین با effective_at <= as_of)
	try:
		res = resolve_rate_to_base(db, business_id, int(document_currency_id), as_of)
		extra["fx"] = _rate_row_to_fx_dict(
			base_id=int(res["base_currency_id"]),
			currency_id=int(res["currency_id"]),
			rate=res["rate"] if isinstance(res["rate"], Decimal) else Decimal(str(res["rate"])),
			effective_at=res["effective_at"] if isinstance(res["effective_at"], datetime) else _to_utc_aware(as_of),
			rate_row_id=res.get("rate_row_id"),
			mode="auto",
		)
	except ApiError as e:
		err = getattr(e, "detail", None)
		code = None
		if isinstance(err, dict) and isinstance(err.get("error"), dict):
			code = err["error"].get("code")
		if code == "RATE_NOT_FOUND" and policy.get("when_no_rate") == "allow_without_fx":
			extra["fx"] = {
				"skipped": True,
				"reason": "no_rate",
				"as_of": as_of.isoformat(),
				"document_currency_id": int(document_currency_id),
				"base_currency_id": int(base_id),
			}
			return extra
		raise
	return extra
