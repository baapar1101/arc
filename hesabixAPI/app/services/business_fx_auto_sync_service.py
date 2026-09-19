"""زمان‌بندی خودکار ثبت نرخ تسعیر کسب‌وکار از اسنپ‌شات مرکزی + آفست per ارز."""

from __future__ import annotations

import logging
import re
from datetime import datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP, InvalidOperation
from typing import Any, Dict, List, Optional, Tuple
from zoneinfo import ZoneInfo

from sqlalchemy import and_, desc, select
from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.business_currency_rate import BusinessCurrencyRate
from adapters.db.models.business_fx_auto_sync import (
	BusinessFxAutoSyncCurrencyRule,
	BusinessFxAutoSyncSettings,
)
from adapters.db.models.currency import BusinessCurrency, Currency
from adapters.db.models.fx_rate_provider import FxGlobalRate, FxRateProvider
from app.core.responses import ApiError
from app.services.fx_rate_provider_service import (
	assert_multi_currency,
	business_is_multi_currency,
	rate_to_business_base,
)

logger = logging.getLogger(__name__)

ALLOWED_INTERVAL_HOURS = {1, 2, 3, 6, 12, 24}
MAX_PERCENT_OFFSET = Decimal("50")
_TIME_RE = re.compile(r"^([01]?\d|2[0-3]):([0-5]\d)$")


def _now_utc() -> datetime:
	return datetime.now(timezone.utc)


def _to_utc_aware(dt: datetime) -> datetime:
	if dt.tzinfo is None:
		return dt.replace(tzinfo=timezone.utc)
	return dt.astimezone(timezone.utc)


def _dec(v: Any, default: Decimal = Decimal(0)) -> Decimal:
	try:
		return Decimal(str(v))
	except (InvalidOperation, TypeError, ValueError):
		return default


def _quantize_rate(rate: Decimal, decimal_places: int) -> Decimal:
	dp = max(0, min(10, int(decimal_places)))
	q = Decimal(1).scaleb(-dp) if dp > 0 else Decimal(1)
	return rate.quantize(q, rounding=ROUND_HALF_UP)


def _parse_daily_times(raw: Any) -> List[str]:
	if raw is None:
		return []
	if not isinstance(raw, list):
		raise ApiError("FX_AUTO_TIMES_INVALID", "daily_times باید آرایه ساعت‌ها باشد", http_status=400)
	out: List[str] = []
	seen: set[str] = set()
	for item in raw:
		s = str(item).strip()
		m = _TIME_RE.match(s)
		if not m:
			raise ApiError(
				"FX_AUTO_TIMES_INVALID",
				f"ساعت نامعتبر: {s} (فرمت HH:MM)",
				http_status=400,
			)
		norm = f"{int(m.group(1)):02d}:{m.group(2)}"
		if norm not in seen:
			seen.add(norm)
			out.append(norm)
	out.sort()
	if len(out) > 12:
		raise ApiError("FX_AUTO_TIMES_INVALID", "حداکثر ۱۲ ساعت در روز مجاز است", http_status=400)
	return out


def _resolve_tz(name: Optional[str]) -> ZoneInfo:
	candidates = [name, "Asia/Tehran", "UTC"]
	for c in candidates:
		if not c:
			continue
		try:
			return ZoneInfo(str(c))
		except Exception:
			continue
	return ZoneInfo("UTC")


def compute_next_run_at(
	*,
	enabled: bool,
	schedule_mode: str,
	interval_hours: Optional[int],
	daily_times: Optional[List[str]],
	timezone_name: Optional[str],
	from_utc: Optional[datetime] = None,
	last_run_at: Optional[datetime] = None,
) -> Optional[datetime]:
	if not enabled:
		return None
	now = _to_utc_aware(from_utc or _now_utc())
	mode = (schedule_mode or "interval").strip().lower()
	if mode == "interval":
		hours = int(interval_hours or 6)
		if hours not in ALLOWED_INTERVAL_HOURS:
			hours = 6
		base = _to_utc_aware(last_run_at) if last_run_at else now
		nxt = base + timedelta(hours=hours)
		if nxt <= now:
			nxt = now + timedelta(hours=hours)
		return nxt

	# daily_times
	times = _parse_daily_times(daily_times or [])
	if not times:
		# fallback: یک‌بار در روز ساعت ۹
		times = ["09:00"]
	tz = _resolve_tz(timezone_name)
	local_now = now.astimezone(tz)
	# امروز و فردا را چک کن
	for day_offset in range(0, 8):
		day = (local_now + timedelta(days=day_offset)).date()
		for t in times:
			hh, mm = map(int, t.split(":"))
			candidate_local = datetime(day.year, day.month, day.day, hh, mm, tzinfo=tz)
			candidate_utc = candidate_local.astimezone(timezone.utc)
			if candidate_utc > now:
				return candidate_utc
	return now + timedelta(days=1)


def apply_offset(
	base_rate: Decimal,
	*,
	offset_type: str,
	offset_direction: str,
	offset_value: Decimal,
) -> Decimal:
	otype = (offset_type or "none").strip().lower()
	if otype in ("", "none"):
		return base_rate
	sign = Decimal(1) if (offset_direction or "up").strip().lower() != "down" else Decimal(-1)
	val = abs(_dec(offset_value))
	if otype == "percent":
		if val > MAX_PERCENT_OFFSET:
			raise ApiError(
				"FX_OFFSET_TOO_LARGE",
				f"آفست درصدی نباید بیشتر از {MAX_PERCENT_OFFSET}٪ باشد",
				http_status=400,
			)
		return base_rate * (Decimal(1) + sign * (val / Decimal(100)))
	if otype == "amount":
		return base_rate + sign * val
	raise ApiError("FX_OFFSET_TYPE_INVALID", "نوع آفست نامعتبر است", http_status=400)


def _serialize_rule(rule: BusinessFxAutoSyncCurrencyRule) -> Dict[str, Any]:
	cur = rule.currency
	return {
		"id": rule.id,
		"currency_id": rule.currency_id,
		"currency": {
			"id": cur.id,
			"code": cur.code,
			"title": cur.title,
			"symbol": cur.symbol,
		}
		if cur
		else None,
		"enabled": bool(rule.enabled),
		"offset_type": rule.offset_type,
		"offset_direction": rule.offset_direction,
		"offset_value": str(rule.offset_value),
	}


def serialize_settings(
	settings: BusinessFxAutoSyncSettings,
	*,
	secondary_currencies: Optional[List[Currency]] = None,
) -> Dict[str, Any]:
	rules = [_serialize_rule(r) for r in (settings.rules or [])]
	# اطمینان از نمایش همه ارزهای فرعی در UI حتی بدون rule ذخیره‌شده
	if secondary_currencies:
		have = {int(r["currency_id"]) for r in rules}
		for c in secondary_currencies:
			if int(c.id) not in have:
				rules.append(
					{
						"id": None,
						"currency_id": c.id,
						"currency": {
							"id": c.id,
							"code": c.code,
							"title": c.title,
							"symbol": c.symbol,
						},
						"enabled": True,
						"offset_type": "none",
						"offset_direction": "up",
						"offset_value": "0",
					}
				)
		rules.sort(key=lambda r: (r.get("currency") or {}).get("code") or "")
	return {
		"business_id": settings.business_id,
		"enabled": bool(settings.enabled),
		"schedule_mode": settings.schedule_mode,
		"interval_hours": settings.interval_hours,
		"daily_times": list(settings.daily_times or []),
		"timezone": settings.timezone,
		"skip_if_unchanged": bool(settings.skip_if_unchanged),
		"min_change_percent": str(settings.min_change_percent),
		"block_if_stale": bool(settings.block_if_stale),
		"stale_after_hours": int(settings.stale_after_hours or 24),
		"updated_by_user_id": settings.updated_by_user_id,
		"last_run_at": settings.last_run_at,
		"last_run_status": settings.last_run_status,
		"last_run_message": settings.last_run_message,
		"next_run_at": settings.next_run_at,
		"source": "central_snapshot",
		"rules": rules,
		"allowed_interval_hours": sorted(ALLOWED_INTERVAL_HOURS),
		"max_percent_offset": str(MAX_PERCENT_OFFSET),
	}


def _secondary_currencies(db: Session, business_id: int, default_id: int) -> List[Currency]:
	return list(
		db.execute(
			select(Currency)
			.join(BusinessCurrency, BusinessCurrency.currency_id == Currency.id)
			.where(
				BusinessCurrency.business_id == int(business_id),
				Currency.id != int(default_id),
			)
			.order_by(Currency.code)
		).scalars().all()
	)


def get_or_create_settings(db: Session, business_id: int) -> BusinessFxAutoSyncSettings:
	row = db.execute(
		select(BusinessFxAutoSyncSettings).where(
			BusinessFxAutoSyncSettings.business_id == int(business_id)
		)
	).scalar_one_or_none()
	if row:
		return row
	now = _now_utc()
	b = db.get(Business, int(business_id))
	tz = getattr(b, "display_timezone", None) if b else None
	row = BusinessFxAutoSyncSettings(
		business_id=int(business_id),
		enabled=False,
		schedule_mode="interval",
		interval_hours=6,
		daily_times=[],
		timezone=tz or "Asia/Tehran",
		skip_if_unchanged=True,
		min_change_percent=Decimal("0.01"),
		block_if_stale=True,
		stale_after_hours=24,
		created_at=now,
		updated_at=now,
	)
	db.add(row)
	db.flush()
	return row


def get_settings_payload(db: Session, business_id: int) -> Dict[str, Any]:
	assert_multi_currency(db, business_id)
	b = db.get(Business, int(business_id))
	if not b or not b.default_currency_id:
		raise ApiError("BUSINESS_CURRENCY", "ارز اصلی تعریف نشده است", http_status=400)
	settings = get_or_create_settings(db, business_id)
	secondaries = _secondary_currencies(db, business_id, int(b.default_currency_id))
	return serialize_settings(settings, secondary_currencies=secondaries)


def _validate_and_normalize_payload(data: Dict[str, Any], business: Business) -> Dict[str, Any]:
	enabled = bool(data.get("enabled", False))
	mode = str(data.get("schedule_mode") or "interval").strip().lower()
	if mode not in ("interval", "daily_times"):
		raise ApiError("FX_AUTO_MODE_INVALID", "حالت زمان‌بندی نامعتبر است", http_status=400)

	interval_hours = data.get("interval_hours")
	if mode == "interval":
		try:
			interval_hours = int(interval_hours if interval_hours is not None else 6)
		except (TypeError, ValueError) as exc:
			raise ApiError("FX_AUTO_INTERVAL_INVALID", "بازه ساعتی نامعتبر است", http_status=400) from exc
		if interval_hours not in ALLOWED_INTERVAL_HOURS:
			raise ApiError(
				"FX_AUTO_INTERVAL_INVALID",
				f"بازه باید یکی از {sorted(ALLOWED_INTERVAL_HOURS)} باشد",
				http_status=400,
			)
	else:
		interval_hours = int(interval_hours) if interval_hours is not None else 6

	daily_times = _parse_daily_times(data.get("daily_times")) if mode == "daily_times" else list(
		data.get("daily_times") or []
	)
	if mode == "daily_times" and not daily_times:
		raise ApiError("FX_AUTO_TIMES_REQUIRED", "حداقل یک ساعت روزانه لازم است", http_status=400)

	tz = data.get("timezone")
	if tz is None or str(tz).strip() == "":
		tz = getattr(business, "display_timezone", None) or "Asia/Tehran"
	else:
		tz = str(tz).strip()
		_resolve_tz(tz)  # validate

	skip_if_unchanged = bool(data.get("skip_if_unchanged", True))
	min_change = _dec(data.get("min_change_percent"), Decimal("0.01"))
	if min_change < 0 or min_change > Decimal("100"):
		raise ApiError("FX_AUTO_MIN_CHANGE_INVALID", "حداقل درصد تغییر نامعتبر است", http_status=400)

	block_if_stale = bool(data.get("block_if_stale", True))
	try:
		stale_after = int(data.get("stale_after_hours") if data.get("stale_after_hours") is not None else 24)
	except (TypeError, ValueError) as exc:
		raise ApiError("FX_AUTO_STALE_INVALID", "آستانه کهنگی نامعتبر است", http_status=400) from exc
	if stale_after < 1 or stale_after > 168:
		raise ApiError("FX_AUTO_STALE_INVALID", "آستانه کهنگی باید بین ۱ تا ۱۶۸ ساعت باشد", http_status=400)

	rules_in = data.get("rules") or []
	if not isinstance(rules_in, list):
		raise ApiError("FX_AUTO_RULES_INVALID", "rules باید آرایه باشد", http_status=400)

	norm_rules: List[Dict[str, Any]] = []
	for raw in rules_in:
		if not isinstance(raw, dict):
			continue
		try:
			cid = int(raw.get("currency_id"))
		except (TypeError, ValueError) as exc:
			raise ApiError("CURRENCY_ID_INVALID", "شناسه ارز نامعتبر است", http_status=400) from exc
		otype = str(raw.get("offset_type") or "none").strip().lower()
		if otype not in ("none", "percent", "amount"):
			raise ApiError("FX_OFFSET_TYPE_INVALID", "نوع آفست نامعتبر است", http_status=400)
		odir = str(raw.get("offset_direction") or "up").strip().lower()
		if odir not in ("up", "down"):
			raise ApiError("FX_OFFSET_DIR_INVALID", "جهت آفست نامعتبر است", http_status=400)
		oval = abs(_dec(raw.get("offset_value")))
		if otype == "percent" and oval > MAX_PERCENT_OFFSET:
			raise ApiError(
				"FX_OFFSET_TOO_LARGE",
				f"آفست درصدی نباید بیشتر از {MAX_PERCENT_OFFSET}٪ باشد",
				http_status=400,
			)
		# validate formula doesn't explode
		if otype != "none":
			_ = apply_offset(Decimal("1000000"), offset_type=otype, offset_direction=odir, offset_value=oval)
		norm_rules.append(
			{
				"currency_id": cid,
				"enabled": bool(raw.get("enabled", True)),
				"offset_type": otype,
				"offset_direction": odir,
				"offset_value": oval,
			}
		)

	return {
		"enabled": enabled,
		"schedule_mode": mode,
		"interval_hours": interval_hours,
		"daily_times": daily_times,
		"timezone": tz,
		"skip_if_unchanged": skip_if_unchanged,
		"min_change_percent": min_change,
		"block_if_stale": block_if_stale,
		"stale_after_hours": stale_after,
		"rules": norm_rules,
	}


def upsert_settings(db: Session, business_id: int, user_id: int, data: Dict[str, Any]) -> Dict[str, Any]:
	assert_multi_currency(db, business_id)
	b = db.get(Business, int(business_id))
	if not b or not b.default_currency_id:
		raise ApiError("BUSINESS_CURRENCY", "ارز اصلی تعریف نشده است", http_status=400)
	norm = _validate_and_normalize_payload(data, b)
	default_id = int(b.default_currency_id)
	secondaries = _secondary_currencies(db, business_id, default_id)
	sec_ids = {int(c.id) for c in secondaries}

	for rule in norm["rules"]:
		if int(rule["currency_id"]) == default_id:
			raise ApiError("CURRENCY_IS_BASE", "برای ارز اصلی آفست تعریف نمی‌شود", http_status=400)
		if int(rule["currency_id"]) not in sec_ids:
			raise ApiError("CURRENCY_NOT_ALLOWED", "ارز در کسب‌وکار فعال نیست", http_status=400)

	settings = get_or_create_settings(db, business_id)
	now = _now_utc()
	settings.enabled = norm["enabled"]
	settings.schedule_mode = norm["schedule_mode"]
	settings.interval_hours = norm["interval_hours"]
	settings.daily_times = norm["daily_times"]
	settings.timezone = norm["timezone"]
	settings.skip_if_unchanged = norm["skip_if_unchanged"]
	settings.min_change_percent = norm["min_change_percent"]
	settings.block_if_stale = norm["block_if_stale"]
	settings.stale_after_hours = norm["stale_after_hours"]
	settings.updated_by_user_id = int(user_id)
	settings.updated_at = now
	# اولین فعال‌سازی بدون اجرای قبلی: نزدیک‌ترین اسلات (تقریباً الان) تا منتظر بازه کامل نماند
	if settings.enabled and settings.last_run_at is None:
		settings.next_run_at = now
	else:
		settings.next_run_at = compute_next_run_at(
			enabled=settings.enabled,
			schedule_mode=settings.schedule_mode,
			interval_hours=settings.interval_hours,
			daily_times=list(settings.daily_times or []),
			timezone_name=settings.timezone,
			from_utc=now,
			last_run_at=settings.last_run_at,
		)

	# sync rules: upsert provided, remove orphans not in payload if payload includes rules key
	existing = {int(r.currency_id): r for r in (settings.rules or [])}
	seen: set[int] = set()
	for rule_data in norm["rules"]:
		cid = int(rule_data["currency_id"])
		seen.add(cid)
		row = existing.get(cid)
		if row is None:
			row = BusinessFxAutoSyncCurrencyRule(
				business_id=int(business_id),
				settings_id=settings.id,
				currency_id=cid,
				created_at=now,
				updated_at=now,
			)
			db.add(row)
			settings.rules.append(row)
		row.enabled = rule_data["enabled"]
		row.offset_type = rule_data["offset_type"]
		row.offset_direction = rule_data["offset_direction"]
		row.offset_value = rule_data["offset_value"]
		row.updated_at = now

	# حذف ruleهایی که دیگر در payload نیستند (اگر rules ارسال شده)
	if "rules" in data:
		for cid, row in list(existing.items()):
			if cid not in seen:
				db.delete(row)

	db.flush()
	db.refresh(settings)
	return serialize_settings(settings, secondary_currencies=secondaries)


def _latest_global_for_code(db: Session, currency_code: str) -> Optional[FxGlobalRate]:
	q = (
		select(FxGlobalRate)
		.join(FxRateProvider, FxGlobalRate.provider_id == FxRateProvider.id)
		.where(FxGlobalRate.currency_code == currency_code.upper())
		.order_by(FxRateProvider.is_active.desc(), FxGlobalRate.fetched_at.desc(), FxGlobalRate.id.desc())
		.limit(1)
	)
	return db.execute(q).scalars().first()


def _latest_business_rate(db: Session, business_id: int, currency_id: int) -> Optional[BusinessCurrencyRate]:
	q = (
		select(BusinessCurrencyRate)
		.where(
			and_(
				BusinessCurrencyRate.business_id == int(business_id),
				BusinessCurrencyRate.currency_id == int(currency_id),
			)
		)
		.order_by(desc(BusinessCurrencyRate.effective_at), desc(BusinessCurrencyRate.id))
		.limit(1)
	)
	return db.execute(q).scalars().first()


def _rule_map(settings: BusinessFxAutoSyncSettings) -> Dict[int, BusinessFxAutoSyncCurrencyRule]:
	return {int(r.currency_id): r for r in (settings.rules or [])}


def _build_preview_items(
	db: Session,
	business: Business,
	settings: BusinessFxAutoSyncSettings,
) -> Tuple[List[Dict[str, Any]], Optional[str]]:
	default_id = int(business.default_currency_id)  # type: ignore[arg-type]
	base = db.get(Currency, default_id)
	base_code = base.code if base else "IRR"
	base_dp = int(getattr(base, "decimal_places", 0) or 0) if base else 0
	secondaries = _secondary_currencies(db, int(business.id), default_id)
	rules = _rule_map(settings)
	now = _now_utc()
	items: List[Dict[str, Any]] = []
	warning: Optional[str] = None

	for cur in secondaries:
		rule = rules.get(int(cur.id))
		enabled = True if rule is None else bool(rule.enabled)
		otype = "none" if rule is None else rule.offset_type
		odir = "up" if rule is None else rule.offset_direction
		oval = Decimal(0) if rule is None else Decimal(str(rule.offset_value or 0))

		g = _latest_global_for_code(db, cur.code)
		ref = None
		final = None
		age_h = None
		status = "ok"
		message = None
		if g is None:
			status = "missing_snapshot"
			message = "اسنپ‌شات مرکزی برای این ارز نیست"
		else:
			fetched = g.fetched_at
			if fetched and fetched.tzinfo is None:
				fetched = fetched.replace(tzinfo=timezone.utc)
			if fetched:
				age_h = round((now - fetched).total_seconds() / 3600.0, 2)
				if settings.block_if_stale and age_h > float(settings.stale_after_hours or 24):
					status = "stale"
					message = f"اسنپ‌شات قدیمی ({age_h} ساعت)"
					warning = warning or "برخی نرخ‌ها کهنه هستند"
			try:
				ref = rate_to_business_base(
					price_irr=Decimal(str(g.price_irr)),
					base_currency_code=base_code,
				)
				final = apply_offset(
					ref,
					offset_type=otype,
					offset_direction=odir,
					offset_value=oval,
				)
				final = _quantize_rate(final, base_dp)
				if final <= 0:
					status = "invalid_rate"
					message = "نرخ نهایی باید بزرگ‌تر از صفر باشد"
					final = None
			except ApiError as e:
				status = "error"
				detail = getattr(e, "detail", None)
				if isinstance(detail, dict) and isinstance(detail.get("error"), dict):
					message = detail["error"].get("message")
				else:
					message = str(e)

		items.append(
			{
				"currency_id": cur.id,
				"currency_code": cur.code,
				"currency_title": cur.title,
				"enabled": enabled,
				"offset_type": otype,
				"offset_direction": odir,
				"offset_value": str(oval),
				"reference_rate": str(ref) if ref is not None else None,
				"final_rate": str(final) if final is not None else None,
				"snapshot_symbol": g.symbol if g else None,
				"snapshot_fetched_at": g.fetched_at if g else None,
				"age_hours": age_h,
				"status": status,
				"message": message,
			}
		)
	return items, warning


def preview_auto_sync(
	db: Session,
	business_id: int,
	draft: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
	assert_multi_currency(db, business_id)
	b = db.get(Business, int(business_id))
	if not b or not b.default_currency_id:
		raise ApiError("BUSINESS_CURRENCY", "ارز اصلی تعریف نشده است", http_status=400)
	settings = get_or_create_settings(db, business_id)
	# پیش‌نمایش با پیش‌نویس UI (بدون ذخیره) — روی کپی در حافظه
	work = settings
	if draft:
		norm = _validate_and_normalize_payload(draft, b)
		# شبیه‌سازی موقت بدون commit
		class _TmpSettings:
			pass

		tmp = _TmpSettings()
		tmp.block_if_stale = norm["block_if_stale"]
		tmp.stale_after_hours = norm["stale_after_hours"]
		tmp.skip_if_unchanged = norm["skip_if_unchanged"]
		tmp.min_change_percent = norm["min_change_percent"]

		class _TmpRule:
			pass

		rules = []
		for r in norm["rules"]:
			tr = _TmpRule()
			tr.currency_id = r["currency_id"]
			tr.enabled = r["enabled"]
			tr.offset_type = r["offset_type"]
			tr.offset_direction = r["offset_direction"]
			tr.offset_value = r["offset_value"]
			rules.append(tr)
		tmp.rules = rules
		work = tmp  # type: ignore[assignment]

	items, warning = _build_preview_items(db, b, work)  # type: ignore[arg-type]
	return {
		"base_currency_code": (b.default_currency.code if b.default_currency else "IRR"),
		"items": items,
		"warning": warning,
		"settings": serialize_settings(
			settings,
			secondary_currencies=_secondary_currencies(db, business_id, int(b.default_currency_id)),
		),
		"draft": bool(draft),
	}


def run_auto_sync_for_business(
	db: Session,
	business_id: int,
	*,
	triggered_by: str = "schedule",
	actor_user_id: Optional[int] = None,
) -> Dict[str, Any]:
	"""اجرای یک‌باره برای یک کسب‌وکار؛ ردیف‌های تسعیر می‌سازد."""
	if not business_is_multi_currency(db, business_id):
		raise ApiError("MULTI_CURRENCY_REQUIRED", "کسب‌وکار چندارزی نیست", http_status=400)
	b = db.get(Business, int(business_id))
	if not b or not b.default_currency_id:
		raise ApiError("BUSINESS_CURRENCY", "ارز اصلی تعریف نشده است", http_status=400)

	settings = get_or_create_settings(db, business_id)
	now = _now_utc()
	items, _warning = _build_preview_items(db, b, settings)
	rules = _rule_map(settings)
	created: List[Dict[str, Any]] = []
	skipped: List[Dict[str, Any]] = []
	errors: List[Dict[str, Any]] = []

	creator_id = actor_user_id or settings.updated_by_user_id or getattr(b, "owner_id", None)
	if creator_id is None:
		raise ApiError(
			"FX_AUTO_NO_ACTOR",
			"کاربر ثبت‌کننده نرخ مشخص نیست؛ تنظیمات را یک‌بار ذخیره کنید.",
			http_status=400,
		)
	base = db.get(Currency, int(b.default_currency_id))
	base_dp = int(getattr(base, "decimal_places", 0) or 0) if base else 0

	for item in items:
		cid = int(item["currency_id"])
		rule = rules.get(cid)
		if rule is not None and not rule.enabled:
			skipped.append({**item, "reason": "disabled"})
			continue
		if item["status"] == "missing_snapshot":
			errors.append({**item, "reason": "missing_snapshot"})
			continue
		if item["status"] == "stale" and settings.block_if_stale:
			errors.append({**item, "reason": "stale"})
			continue
		if item["status"] in ("invalid_rate", "error") or item.get("final_rate") is None:
			errors.append({**item, "reason": item.get("status") or "error"})
			continue

		final = _dec(item["final_rate"])
		final = _quantize_rate(final, base_dp)
		if settings.skip_if_unchanged:
			prev = _latest_business_rate(db, business_id, cid)
			if prev is not None:
				prev_rate = Decimal(str(prev.rate))
				if prev_rate > 0:
					change_pct = abs((final - prev_rate) / prev_rate) * Decimal(100)
					if change_pct < Decimal(str(settings.min_change_percent or 0)):
						skipped.append(
							{
								**item,
								"reason": "unchanged",
								"previous_rate": str(prev_rate),
								"change_percent": str(change_pct),
							}
						)
						continue

		ref = item.get("reference_rate")
		otype = item.get("offset_type") or "none"
		odir = item.get("offset_direction") or "up"
		oval = item.get("offset_value") or "0"
		offset_label = "بدون آفست"
		if otype == "percent":
			offset_label = f"آفست {'+' if odir == 'up' else '-'}{oval}%"
		elif otype == "amount":
			offset_label = f"آفست {'+' if odir == 'up' else '-'}{oval}"

		note = (
			f"خودکار ({triggered_by}) | اسنپ‌شات مرکزی | {offset_label} | "
			f"ref={ref} | {item.get('snapshot_symbol')} @ {item.get('snapshot_fetched_at')}"
		)
		row = BusinessCurrencyRate(
			business_id=int(business_id),
			currency_id=cid,
			effective_at=now,
			rate=final,
			note=note[:2000],
			created_by_user_id=int(creator_id),
			created_at=now,
			updated_at=now,
		)
		db.add(row)
		db.flush()
		created.append(
			{
				"id": row.id,
				"currency_id": cid,
				"currency_code": item.get("currency_code"),
				"rate": str(row.rate),
				"reference_rate": ref,
				"effective_at": row.effective_at,
				"note": row.note,
			}
		)

	if errors and not created and not skipped:
		status = "error"
		message = "هیچ نرخی ثبت نشد؛ اسنپ‌شات موجود/معتبر نیست"
	elif errors and created:
		status = "partial"
		message = f"{len(created)} ثبت، {len(skipped)} رد، {len(errors)} خطا"
	elif created:
		status = "ok"
		message = f"{len(created)} نرخ ثبت شد"
		if skipped:
			message += f"؛ {len(skipped)} بدون تغییر رد شد"
	else:
		status = "ok"
		message = f"بدون تغییر ({len(skipped)} مورد)"

	settings.last_run_at = now
	settings.last_run_status = status
	settings.last_run_message = message
	settings.next_run_at = compute_next_run_at(
		enabled=settings.enabled,
		schedule_mode=settings.schedule_mode,
		interval_hours=settings.interval_hours,
		daily_times=list(settings.daily_times or []),
		timezone_name=settings.timezone,
		from_utc=now,
		last_run_at=now,
	)
	settings.updated_at = now
	db.flush()

	return {
		"status": status,
		"message": message,
		"created": created,
		"skipped": skipped,
		"errors": errors,
		"next_run_at": settings.next_run_at,
		"last_run_at": settings.last_run_at,
	}


def list_due_business_ids(db: Session, *, limit: int = 50, now: Optional[datetime] = None) -> List[int]:
	now = _to_utc_aware(now or _now_utc())
	q = (
		select(BusinessFxAutoSyncSettings.business_id)
		.where(
			BusinessFxAutoSyncSettings.enabled == True,  # noqa: E712
			BusinessFxAutoSyncSettings.next_run_at.is_not(None),
			BusinessFxAutoSyncSettings.next_run_at <= now,
		)
		.order_by(BusinessFxAutoSyncSettings.next_run_at.asc())
		.limit(max(1, min(200, int(limit))))
	)
	return [int(x) for x in db.execute(q).scalars().all()]
