from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import and_, func, literal, select, update
from sqlalchemy.orm import Session

from adapters.db.models.notification import NotificationOutbox
from app.core.cache import get_cache
from app.core.responses import ApiError
from app.core.settings import get_settings
from app.services.notification_service import OUTBOX_MAX_RETRY_COUNT
from app.services.system_settings_service import get_sms_destination_rate_effective

ABANDON_CONFIRM_PHRASE = "ABANDON_OUTBOX_QUEUE"


def get_notification_outbox_summary(db: Session) -> dict[str, Any]:
	"""آمار صف outbox برای مانیتورینگ (سبک: بدون full-scan کل جدول)."""
	settings = get_settings()
	now = datetime.utcnow()
	cut_24h = now - timedelta(hours=24)
	cut_7d = now - timedelta(days=7)

	retry_due_now = int(
		db.scalar(
			select(func.count())
			.select_from(NotificationOutbox)
			.where(
				and_(
					NotificationOutbox.status == "failed",
					NotificationOutbox.next_attempt_at.is_not(None),
					NotificationOutbox.next_attempt_at <= now,
				)
			)
		)
		or 0
	)

	retry_scheduled_future = int(
		db.scalar(
			select(func.count())
			.select_from(NotificationOutbox)
			.where(
				and_(
					NotificationOutbox.status == "failed",
					NotificationOutbox.next_attempt_at.is_not(None),
					NotificationOutbox.next_attempt_at > now,
				)
			)
		)
		or 0
	)

	pending_sms = int(
		db.scalar(
			select(func.count())
			.select_from(NotificationOutbox)
			.where(
				and_(
					NotificationOutbox.status == "pending",
					NotificationOutbox.channel == "sms",
				)
			)
		)
		or 0
	)

	pending_all = int(
		db.scalar(
			select(func.count()).select_from(NotificationOutbox).where(NotificationOutbox.status == "pending")
		)
		or 0
	)

	stmt_24h = (
		select(NotificationOutbox.status, func.count())
		.where(NotificationOutbox.created_at >= cut_24h)
		.group_by(NotificationOutbox.status)
	)
	by_status_24h = {row[0]: int(row[1]) for row in db.execute(stmt_24h).all()}

	sms_created_24h = int(
		db.scalar(
			select(func.count())
			.select_from(NotificationOutbox)
			.where(
				and_(
					NotificationOutbox.channel == "sms",
					NotificationOutbox.created_at >= cut_24h,
				)
			)
		)
		or 0
	)

	top_failed_sms = [
		{"event_key": row[0], "count": int(row[1])}
		for row in db.execute(
			select(NotificationOutbox.event_key, func.count())
			.where(
				and_(
					NotificationOutbox.channel == "sms",
					NotificationOutbox.status == "failed",
					NotificationOutbox.created_at >= cut_7d,
				)
			)
			.group_by(NotificationOutbox.event_key)
			.order_by(func.count().desc())
			.limit(15)
		).all()
	]

	oldest_due = db.scalar(
		select(func.min(NotificationOutbox.next_attempt_at)).where(
			and_(
				NotificationOutbox.status == "failed",
				NotificationOutbox.next_attempt_at.is_not(None),
				NotificationOutbox.next_attempt_at <= now,
			)
		)
	)

	dest_enabled, dest_max, dest_win = get_sms_destination_rate_effective(db)
	cache = get_cache()

	warnings: list[dict[str, str]] = []
	if retry_due_now >= settings.monitoring_outbox_due_retry_warn:
		warnings.append(
			{
				"code": "outbox_retry_due_high",
				"message": (
					f"تعداد ردیف‌های آمادهٔ retry ({retry_due_now}) از آستانهٔ "
					f"({settings.monitoring_outbox_due_retry_warn}) بیشتر است."
				),
			}
		)
	if pending_sms >= settings.monitoring_outbox_sms_pending_warn:
		warnings.append(
			{
				"code": "outbox_sms_pending_high",
				"message": (
					f"پیامک در وضعیت pending ({pending_sms}) از آستانهٔ "
					f"({settings.monitoring_outbox_sms_pending_warn}) بیشتر است."
				),
			}
		)
	if not cache.enabled:
		warnings.append(
			{
				"code": "redis_cache_off",
				"message": "Redis متصل نیست؛ محدودیت نرخ درخواست ممکن است بین workerها یکپارچه نباشد.",
			}
		)

	return {
		"generated_at_utc": now.isoformat() + "Z",
		"outbox_max_retry_per_row": OUTBOX_MAX_RETRY_COUNT,
		"retry_queue": {
			"failed_due_now": retry_due_now,
			"failed_scheduled_future": retry_scheduled_future,
			"oldest_due_at_utc": oldest_due.isoformat() if oldest_due else None,
		},
		"pending": {"sms": pending_sms, "all_channels": pending_all},
		"created_last_24h": {
			"by_status": by_status_24h,
			"sms_total": sms_created_24h,
		},
		"top_failed_sms_events_7d": top_failed_sms,
		"sms_destination_rate": {
			"enabled": dest_enabled,
			"max_sends_per_window": dest_max,
			"window_minutes": dest_win,
		},
		"redis_cache_enabled": cache.enabled,
		"thresholds": {
			"due_retry_warn": settings.monitoring_outbox_due_retry_warn,
			"sms_pending_warn": settings.monitoring_outbox_sms_pending_warn,
		},
		"warnings": warnings,
		"abandon_confirm_phrase": ABANDON_CONFIRM_PHRASE,
	}


def abandon_outbox_rows(
	db: Session,
	*,
	confirm_phrase: str,
	statuses: list[str],
	channel: str | None,
	event_key: str | None,
	user_id: int | None,
	only_retry_scheduled: bool,
	max_rows: int,
	admin_note: str | None,
) -> int:
	if confirm_phrase != ABANDON_CONFIRM_PHRASE:
		raise ApiError(
			"CONFIRM_REQUIRED",
			"برای خالی کردن صف باید عبارت تأیید صحیح ارسال شود.",
			http_status=400,
		)
	if max_rows < 1 or max_rows > 500_000:
		raise ApiError("INVALID_LIMIT", "max_rows باید بین 1 و 500000 باشد", http_status=400)
	for st in statuses:
		if st not in ("failed", "pending"):
			raise ApiError("INVALID_STATUS", "فقط failed یا pending مجاز است", http_status=400)

	note = (admin_note or "panel_abandon").strip()[:120]
	suffix = f" | admin_abandon:{note}"

	conditions = [NotificationOutbox.status.in_(tuple(statuses))]
	if channel:
		conditions.append(NotificationOutbox.channel == channel)
	if event_key:
		conditions.append(NotificationOutbox.event_key == event_key)
	if user_id is not None:
		conditions.append(NotificationOutbox.user_id == user_id)
	if only_retry_scheduled:
		conditions.append(NotificationOutbox.next_attempt_at.is_not(None))

	total_updated = 0
	batch = 25_000
	while total_updated < max_rows:
		lim = min(batch, max_rows - total_updated)
		ids = list(
			db.scalars(select(NotificationOutbox.id).where(and_(*conditions)).limit(lim)).all()
		)
		if not ids:
			break
		db.execute(
			update(NotificationOutbox)
			.where(NotificationOutbox.id.in_(ids))
			.values(
				status="abandoned",
				next_attempt_at=None,
				updated_at=datetime.utcnow(),
				error_message=func.left(
					func.concat(func.coalesce(NotificationOutbox.error_message, ""), literal(suffix)),
					2000,
				),
			)
		)
		db.commit()
		total_updated += len(ids)

	return total_updated
