"""CRUD و اجرای زمان‌بندی گزارش‌های HScript."""

from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Any, Optional
from zoneinfo import ZoneInfo

from croniter import croniter
from sqlalchemy.orm import Session

from adapters.db.models.hscript_report import HScriptReport, HScriptReportSchedule
from app.core.datetime_utils import utc_now_aware
from app.core.responses import ApiError
from app.services.hscript.plan_limits import resolve_hscript_entitlement
from app.services.workflow.schedule_cron_resolution import resolve_schedule_config_to_cron

logger = logging.getLogger(__name__)

_ALLOWED_FORMATS = {"pdf", "excel", "none"}
_ALLOWED_CHANNELS = {"inapp", "email"}


def _schedule_config(row: HScriptReportSchedule) -> dict[str, Any]:
	if (row.schedule_mode or "simple") == "cron":
		return {"schedule_mode": "cron", "schedule": row.cron_expression or ""}
	return {
		"schedule_mode": "simple",
		"simple_repeat": row.simple_repeat or "daily",
		"simple_time": row.simple_time or "08:00",
		"simple_weekday": row.simple_weekday if row.simple_weekday is not None else 0,
		"simple_interval": row.simple_interval if row.simple_interval is not None else 1,
	}


def resolve_cron(row: HScriptReportSchedule) -> str:
	return resolve_schedule_config_to_cron(_schedule_config(row)).strip()


def compute_next_run_at(
	*,
	enabled: bool,
	cron_expr: str,
	timezone_name: str,
	from_utc: datetime | None = None,
) -> datetime | None:
	if not enabled or not cron_expr:
		return None
	now = from_utc or utc_now_aware()
	if now.tzinfo is None:
		from datetime import timezone

		now = now.replace(tzinfo=timezone.utc)
	try:
		tz = ZoneInfo(timezone_name or "Asia/Tehran")
	except Exception:
		tz = ZoneInfo("Asia/Tehran")
	local_naive = now.astimezone(tz).replace(tzinfo=None)
	try:
		itr = croniter(cron_expr, local_naive)
		nxt_local = itr.get_next(datetime)
	except Exception as exc:
		logger.warning("HScript schedule cron invalid: %s (%s)", cron_expr, exc)
		return None
	aware_local = nxt_local.replace(tzinfo=tz)
	return aware_local.astimezone(now.tzinfo)


def serialize_schedule(row: HScriptReportSchedule, *, report_title: str | None = None) -> dict[str, Any]:
	return {
		"id": row.id,
		"business_id": row.business_id,
		"report_id": row.report_id,
		"report_title": report_title,
		"title": row.title,
		"enabled": row.enabled,
		"schedule_mode": row.schedule_mode,
		"simple_repeat": row.simple_repeat,
		"simple_time": row.simple_time,
		"simple_weekday": row.simple_weekday,
		"simple_interval": row.simple_interval,
		"cron_expression": row.cron_expression,
		"resolved_cron": resolve_cron(row) or None,
		"timezone": row.timezone,
		"output_format": row.output_format,
		"channels": list(row.channels or ["inapp"]),
		"recipient_user_ids": list(row.recipient_user_ids or []),
		"params": row.params or {},
		"next_run_at": row.next_run_at.isoformat() if row.next_run_at else None,
		"last_run_at": row.last_run_at.isoformat() if row.last_run_at else None,
		"last_run_status": row.last_run_status,
		"last_run_message": row.last_run_message,
		"created_by_user_id": row.created_by_user_id,
		"updated_by_user_id": row.updated_by_user_id,
		"created_at": row.created_at.isoformat() if row.created_at else None,
		"updated_at": row.updated_at.isoformat() if row.updated_at else None,
	}


def _get_published_report(db: Session, business_id: int, report_id: int) -> HScriptReport:
	row = (
		db.query(HScriptReport)
		.filter(
			HScriptReport.id == report_id,
			HScriptReport.business_id == business_id,
			HScriptReport.is_deleted.is_(False),
		)
		.first()
	)
	if not row:
		raise ApiError("HSCRIPT_REPORT_NOT_FOUND", "گزارش یافت نشد", http_status=404)
	if row.status != "published":
		raise ApiError(
			"HSCRIPT_REPORT_NOT_PUBLISHED",
			"فقط گزارش‌های منتشرشده قابل زمان‌بندی هستند.",
			http_status=400,
		)
	return row


def _get_schedule(db: Session, business_id: int, schedule_id: int) -> HScriptReportSchedule:
	row = (
		db.query(HScriptReportSchedule)
		.filter(
			HScriptReportSchedule.id == schedule_id,
			HScriptReportSchedule.business_id == business_id,
		)
		.first()
	)
	if not row:
		raise ApiError("HSCRIPT_SCHEDULE_NOT_FOUND", "زمان‌بندی یافت نشد", http_status=404)
	return row


def count_schedules(db: Session, business_id: int) -> int:
	return (
		db.query(HScriptReportSchedule.id)
		.filter(HScriptReportSchedule.business_id == business_id)
		.count()
	)


def _normalize_payload(data: dict[str, Any]) -> dict[str, Any]:
	mode = str(data.get("schedule_mode") or "simple").strip().lower()
	if mode not in {"simple", "cron"}:
		raise ApiError("INVALID_SCHEDULE_MODE", "schedule_mode باید simple یا cron باشد", http_status=400)
	fmt = str(data.get("output_format") or "pdf").strip().lower()
	if fmt not in _ALLOWED_FORMATS:
		raise ApiError("INVALID_OUTPUT_FORMAT", "output_format باید pdf یا excel یا none باشد", http_status=400)
	channels_raw = data.get("channels") or ["inapp"]
	if not isinstance(channels_raw, list) or not channels_raw:
		channels_raw = ["inapp"]
	channels = []
	for c in channels_raw:
		cs = str(c).strip().lower()
		if cs in _ALLOWED_CHANNELS and cs not in channels:
			channels.append(cs)
	if not channels:
		channels = ["inapp"]
	recipients = data.get("recipient_user_ids") or []
	if not isinstance(recipients, list):
		recipients = []
	clean_recipients = []
	for uid in recipients:
		try:
			clean_recipients.append(int(uid))
		except (TypeError, ValueError):
			continue
	tz = str(data.get("timezone") or "Asia/Tehran").strip() or "Asia/Tehran"
	try:
		ZoneInfo(tz)
	except Exception as exc:
		raise ApiError("INVALID_TIMEZONE", "منطقه زمانی نامعتبر است", http_status=400) from exc

	out: dict[str, Any] = {
		"title": str(data.get("title") or "").strip()[:255],
		"enabled": bool(data.get("enabled", True)),
		"schedule_mode": mode,
		"timezone": tz,
		"output_format": fmt,
		"channels": channels,
		"recipient_user_ids": clean_recipients[:50],
		"params": data.get("params") if isinstance(data.get("params"), dict) else {},
	}
	if mode == "cron":
		cron = str(data.get("cron_expression") or "").strip()
		if not cron:
			raise ApiError("INVALID_CRON", "عبارت cron الزامی است", http_status=400)
		out["cron_expression"] = cron[:120]
		out["simple_repeat"] = None
		out["simple_time"] = None
		out["simple_weekday"] = None
		out["simple_interval"] = None
	else:
		repeat = str(data.get("simple_repeat") or "daily").strip().lower()
		if repeat not in {"daily", "weekly", "every_hours"}:
			raise ApiError("INVALID_SIMPLE_REPEAT", "تکرار ساده نامعتبر است", http_status=400)
		out["simple_repeat"] = repeat
		out["simple_time"] = str(data.get("simple_time") or "08:00")[:8]
		try:
			out["simple_weekday"] = max(0, min(6, int(data.get("simple_weekday", 0))))
		except (TypeError, ValueError):
			out["simple_weekday"] = 0
		try:
			out["simple_interval"] = max(1, min(23, int(data.get("simple_interval", 1))))
		except (TypeError, ValueError):
			out["simple_interval"] = 1
		out["cron_expression"] = None

	# اعتبارسنجی کرون نهایی
	probe = HScriptReportSchedule(
		business_id=0,
		report_id=0,
		schedule_mode=out["schedule_mode"],
		simple_repeat=out.get("simple_repeat"),
		simple_time=out.get("simple_time"),
		simple_weekday=out.get("simple_weekday"),
		simple_interval=out.get("simple_interval"),
		cron_expression=out.get("cron_expression"),
		timezone=out["timezone"],
		enabled=True,
	)
	cron_final = resolve_cron(probe)
	if not cron_final:
		raise ApiError("INVALID_SCHEDULE", "زمان‌بندی قابل تبدیل به cron نیست", http_status=400)
	return out


def list_schedules(
	db: Session,
	business_id: int,
	*,
	report_id: int | None = None,
) -> dict[str, Any]:
	q = db.query(HScriptReportSchedule).filter(HScriptReportSchedule.business_id == business_id)
	if report_id is not None:
		q = q.filter(HScriptReportSchedule.report_id == report_id)
	rows = q.order_by(HScriptReportSchedule.id.desc()).limit(200).all()
	report_ids = {r.report_id for r in rows}
	titles = {}
	if report_ids:
		for rep in (
			db.query(HScriptReport.id, HScriptReport.title)
			.filter(HScriptReport.business_id == business_id, HScriptReport.id.in_(report_ids))
			.all()
		):
			titles[rep.id] = rep.title
	items = [serialize_schedule(r, report_title=titles.get(r.report_id)) for r in rows]
	return {"items": items, "total": len(items)}


def create_schedule(
	db: Session,
	business_id: int,
	*,
	user_id: int,
	report_id: int,
	data: dict[str, Any],
) -> dict[str, Any]:
	report = _get_published_report(db, business_id, report_id)
	ent = resolve_hscript_entitlement(db, business_id)
	max_schedules = int(ent.max_schedules)
	if count_schedules(db, business_id) >= max_schedules:
		raise ApiError(
			"HSCRIPT_SCHEDULE_LIMIT",
			f"سقف تعداد زمان‌بندی در پلن فعلی {max_schedules} است.",
			http_status=403,
			details=ent.to_public_dict(),
		)
	norm = _normalize_payload(data)
	title = norm["title"] or f"زمان‌بندی {report.title}"
	row = HScriptReportSchedule(
		business_id=business_id,
		report_id=report.id,
		title=title,
		enabled=norm["enabled"],
		schedule_mode=norm["schedule_mode"],
		simple_repeat=norm.get("simple_repeat"),
		simple_time=norm.get("simple_time"),
		simple_weekday=norm.get("simple_weekday"),
		simple_interval=norm.get("simple_interval"),
		cron_expression=norm.get("cron_expression"),
		timezone=norm["timezone"],
		output_format=norm["output_format"],
		channels=norm["channels"],
		recipient_user_ids=norm["recipient_user_ids"] or [user_id],
		params=norm["params"],
		created_by_user_id=user_id,
		updated_by_user_id=user_id,
		created_at=utc_now_aware(),
		updated_at=utc_now_aware(),
	)
	row.next_run_at = compute_next_run_at(
		enabled=row.enabled,
		cron_expr=resolve_cron(row),
		timezone_name=row.timezone,
	)
	db.add(row)
	db.commit()
	db.refresh(row)
	return serialize_schedule(row, report_title=report.title)


def update_schedule(
	db: Session,
	business_id: int,
	schedule_id: int,
	*,
	user_id: int,
	data: dict[str, Any],
) -> dict[str, Any]:
	row = _get_schedule(db, business_id, schedule_id)
	report = _get_published_report(db, business_id, row.report_id)
	norm = _normalize_payload({**serialize_schedule(row), **data})
	row.title = norm["title"] or row.title
	row.enabled = norm["enabled"]
	row.schedule_mode = norm["schedule_mode"]
	row.simple_repeat = norm.get("simple_repeat")
	row.simple_time = norm.get("simple_time")
	row.simple_weekday = norm.get("simple_weekday")
	row.simple_interval = norm.get("simple_interval")
	row.cron_expression = norm.get("cron_expression")
	row.timezone = norm["timezone"]
	row.output_format = norm["output_format"]
	row.channels = norm["channels"]
	row.recipient_user_ids = norm["recipient_user_ids"] or row.recipient_user_ids
	row.params = norm["params"]
	row.updated_by_user_id = user_id
	row.updated_at = utc_now_aware()
	row.next_run_at = compute_next_run_at(
		enabled=row.enabled,
		cron_expr=resolve_cron(row),
		timezone_name=row.timezone,
	)
	db.commit()
	db.refresh(row)
	return serialize_schedule(row, report_title=report.title)


def delete_schedule(db: Session, business_id: int, schedule_id: int) -> dict[str, Any]:
	row = _get_schedule(db, business_id, schedule_id)
	db.delete(row)
	db.commit()
	return {"deleted": True, "id": schedule_id}


def list_due_schedules(db: Session, *, limit: int = 40) -> list[HScriptReportSchedule]:
	now = utc_now_aware()
	return (
		db.query(HScriptReportSchedule)
		.filter(
			HScriptReportSchedule.enabled.is_(True),
			HScriptReportSchedule.next_run_at.isnot(None),
			HScriptReportSchedule.next_run_at <= now,
		)
		.order_by(HScriptReportSchedule.next_run_at.asc())
		.limit(max(1, min(int(limit), 100)))
		.all()
	)


def run_schedule_now(
	db: Session,
	schedule: HScriptReportSchedule,
	*,
	triggered_by: str = "schedule",
) -> dict[str, Any]:
	"""اجرای یک زمان‌بندی due و تحویل خروجی."""
	from app.services import hscript_report_service as report_svc

	now = utc_now_aware()
	report = (
		db.query(HScriptReport)
		.filter(
			HScriptReport.id == schedule.report_id,
			HScriptReport.business_id == schedule.business_id,
			HScriptReport.is_deleted.is_(False),
		)
		.first()
	)
	if not report or report.status != "published":
		schedule.enabled = False
		schedule.last_run_at = now
		schedule.last_run_status = "disabled"
		schedule.last_run_message = "گزارش منتشرشده نیست؛ زمان‌بندی خاموش شد"
		schedule.next_run_at = None
		schedule.updated_at = now
		db.commit()
		return {"ok": False, "reason": "report_not_published"}

	actor_id = schedule.created_by_user_id or schedule.updated_by_user_id
	try:
		result = report_svc.run_report(
			db,
			schedule.business_id,
			user_id=int(actor_id or 0) or 0,
			report_id=schedule.report_id,
			params=schedule.params or {},
			preview=False,
			persist=True,
			calendar_type="jalali",
		)
	except Exception as exc:  # noqa: BLE001
		schedule.last_run_at = now
		schedule.last_run_status = "error"
		schedule.last_run_message = str(exc)[:2000]
		schedule.next_run_at = compute_next_run_at(
			enabled=schedule.enabled,
			cron_expr=resolve_cron(schedule),
			timezone_name=schedule.timezone,
			from_utc=now,
		) or (now + timedelta(hours=1))
		schedule.updated_at = now
		db.commit()
		return {"ok": False, "reason": "run_failed", "error": str(exc)}

	delivery = {"notified": 0, "emailed": 0}
	if result.get("ok"):
		try:
			delivery = _deliver_schedule_result(
				db,
				schedule=schedule,
				report=report,
				result=result,
			)
		except Exception as exc:  # noqa: BLE001
			logger.exception("HScript schedule delivery failed: %s", exc)
			schedule.last_run_message = f"اجرا موفق؛ تحویل ناقص: {exc}"[:2000]
			schedule.last_run_status = "partial"
		else:
			schedule.last_run_status = "success"
			schedule.last_run_message = (
				f"تحویل شد · inapp={delivery.get('notified', 0)} · email={delivery.get('emailed', 0)}"
			)[:2000]
	else:
		err = result.get("error") or {}
		schedule.last_run_status = "error"
		schedule.last_run_message = str(err.get("message") or "اجرا ناموفق")[:2000]

	schedule.last_run_at = now
	schedule.next_run_at = compute_next_run_at(
		enabled=schedule.enabled,
		cron_expr=resolve_cron(schedule),
		timezone_name=schedule.timezone,
		from_utc=now,
	)
	schedule.updated_at = now
	db.commit()
	return {
		"ok": bool(result.get("ok")),
		"schedule_id": schedule.id,
		"report_id": schedule.report_id,
		"triggered_by": triggered_by,
		"delivery": delivery,
		"run": {"ok": result.get("ok"), "run_id": result.get("run_id"), "error": result.get("error")},
	}


def _deliver_schedule_result(
	db: Session,
	*,
	schedule: HScriptReportSchedule,
	report: HScriptReport,
	result: dict[str, Any],
) -> dict[str, Any]:
	from adapters.db.models.user import User
	from app.services.email_service import EmailService
	from app.services.notification_service import NotificationService

	channels = [str(c).lower() for c in (schedule.channels or ["inapp"])]
	recipient_ids = list(schedule.recipient_user_ids or [])
	if not recipient_ids and schedule.created_by_user_id:
		recipient_ids = [schedule.created_by_user_id]

	attachment_bytes: bytes | None = None
	filename = f"{report.slug or 'hscript-report'}"
	fmt = (schedule.output_format or "pdf").lower()
	spec = result.get("spec") if isinstance(result.get("spec"), dict) else None

	if fmt in {"pdf", "excel"} and spec is not None:
		from app.services import hscript_report_service as report_svc

		if fmt == "pdf":
			attachment_bytes, filename = report_svc.export_pdf(
				db,
				schedule.business_id,
				user_id=int(schedule.created_by_user_id or 0),
				spec=spec,
				params=schedule.params or {},
			)
		else:
			attachment_bytes, filename = report_svc.export_excel(
				db,
				schedule.business_id,
				user_id=int(schedule.created_by_user_id or 0),
				spec=spec,
				params=schedule.params or {},
			)

	notified = 0
	emailed = 0
	title = schedule.title or report.title
	message = f"گزارش زمان‌بندی‌شده «{title}» آماده شد."
	link = f"/business/{schedule.business_id}/hscript/run/{report.id}"

	ns = NotificationService(db)
	email_svc = EmailService(db)

	for uid in recipient_ids:
		user = db.get(User, int(uid))
		if not user:
			continue
		if "inapp" in channels:
			try:
				ns.send(
					user_id=int(uid),
					event_key="system.info",
					context={
						"subject": f"گزارش HScript: {title}",
						"message": message,
						"link": link,
						"business_id": schedule.business_id,
						"report_id": report.id,
						"schedule_id": schedule.id,
					},
					preferred_channels=["inapp"],
					broadcast_mode=False,
				)
				notified += 1
			except Exception as exc:  # noqa: BLE001
				logger.warning("inapp notify failed uid=%s: %s", uid, exc)
		if "email" in channels and attachment_bytes and getattr(user, "email", None):
			try:
				ok = email_svc.send_email_with_attachment(
					to=str(user.email),
					subject=f"گزارش زمان‌بندی‌شده: {title}",
					body=message + f"\n\nلینک پنل: {link}",
					attachment_filename=filename,
					attachment_content=attachment_bytes,
				)
				if ok:
					emailed += 1
			except Exception as exc:  # noqa: BLE001
				logger.warning("email deliver failed uid=%s: %s", uid, exc)
		elif "email" in channels and getattr(user, "email", None) and not attachment_bytes:
			try:
				ok = email_svc.send_email(
					to=str(user.email),
					subject=f"گزارش زمان‌بندی‌شده: {title}",
					body=message + f"\n\nلینک پنل: {link}",
				)
				if ok:
					emailed += 1
			except Exception as exc:  # noqa: BLE001
				logger.warning("email text failed uid=%s: %s", uid, exc)

	return {"notified": notified, "emailed": emailed, "recipients": len(recipient_ids)}
