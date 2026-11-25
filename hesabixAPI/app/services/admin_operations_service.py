"""خانه عملیاتی، زمان‌بندی‌ها، گزارش‌های سیستمی و انقضای لایسنس."""

from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from adapters.db.models.ai_eval_schedule import AIEvalSchedule
from adapters.db.models.business import Business
from adapters.db.models.file_storage import FileStorage
from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin
from adapters.db.models.workflow import Workflow, WorkflowStatus
from app.services.ai.ai_eval_schedule_service import schedule_to_dict
from app.services.auth_security_event_service import get_auth_security_report
from app.services.notification_outbox_monitoring_service import get_notification_outbox_summary
from app.services.support.support_billing_stats_service import get_support_billing_stats
from app.services.workflow.schedule_cron_resolution import resolve_schedule_config_to_cron

logger = logging.getLogger(__name__)

_FAIL_EVENTS = {
	"login_password_failed",
	"login_failed",
	"captcha_failed",
	"otp_failed",
}


def operations_home(db: Session) -> dict[str, Any]:
	def _safe(label: str, fn):
		try:
			return fn()
		except Exception:
			logger.exception("operations_home_%s_failed", label)
			db.rollback()
			return None

	outbox = _safe("outbox", lambda: get_notification_outbox_summary(db)) or {}
	auth = _safe("auth", lambda: get_auth_security_report(db, hours=24, limit=20)) or {}
	by_type = auth.get("by_type") or {}
	failed_logins = sum(int(by_type.get(key, 0) or 0) for key in _FAIL_EVENTS)
	if failed_logins == 0:
		failed_logins = sum(
			int(count or 0)
			for key, count in by_type.items()
			if "fail" in str(key).lower() or "invalid" in str(key).lower()
		)

	def _storage():
		storage_bytes = int(
			db.query(func.coalesce(func.sum(FileStorage.file_size), 0))
			.filter(FileStorage.deleted_at.is_(None), FileStorage.is_active.is_(True))
			.scalar()
			or 0
		)
		file_count = int(
			db.query(func.count(FileStorage.id))
			.filter(FileStorage.deleted_at.is_(None), FileStorage.is_active.is_(True))
			.scalar()
			or 0
		)
		return {"bytes": storage_bytes, "files": file_count}

	def _businesses():
		stale_before = datetime.utcnow() - timedelta(days=90)
		inactive_businesses = int(
			db.query(func.count(Business.id))
			.filter(Business.deleted_at.is_(None), Business.updated_at < stale_before)
			.scalar()
			or 0
		)
		deleted_businesses = int(
			db.query(func.count(Business.id)).filter(Business.deleted_at.isnot(None)).scalar() or 0
		)
		return {"inactive_90d": inactive_businesses, "deleted": deleted_businesses}

	storage = _safe("storage", _storage) or {"bytes": None, "files": None}
	businesses = _safe("businesses", _businesses) or {"inactive_90d": None, "deleted": None}
	support = _safe("support", lambda: get_support_billing_stats(db) or {}) or {}
	schedules = _safe("schedules", lambda: list_schedules(db)) or {"workflows": [], "ai_eval": {}}
	return {
		"outbox": {
			"retry_due_now": (outbox.get("retry_queue") or {}).get("failed_due_now"),
			"pending": (outbox.get("pending") or {}).get("all_channels"),
			"pending_sms": (outbox.get("pending") or {}).get("sms"),
			"warnings": outbox.get("warnings") or [],
			"abandon_confirm_phrase": outbox.get("abandon_confirm_phrase"),
		},
		"auth_24h": {
			"total": auth.get("total"),
			"failed_logins": failed_logins,
			"by_type": by_type,
		},
		"storage": storage,
		"businesses": businesses,
		"support_billing": support,
		"scheduled_jobs": {
			"workflow_cron": len(schedules.get("workflows") or []),
			"ai_eval_enabled": bool((schedules.get("ai_eval") or {}).get("enabled")),
		},
	}


def list_schedules(db: Session) -> dict[str, Any]:
	try:
		ai_row = db.query(AIEvalSchedule).filter(AIEvalSchedule.id == 1).first()
		ai_eval = schedule_to_dict(ai_row) if ai_row else {
			"enabled": False,
			"cron_expression": None,
			"timezone": "Asia/Tehran",
		}
	except Exception:
		logger.exception("list_schedules_ai_eval_failed")
		db.rollback()
		ai_eval = {"enabled": False, "cron_expression": None, "timezone": "Asia/Tehran"}
	try:
		workflows = (
			db.query(Workflow)
			.filter(Workflow.status == WorkflowStatus.ACTIVE)
			.order_by(Workflow.id.desc())
			.limit(300)
			.all()
		)
	except Exception:
		logger.exception("list_schedules_workflows_failed")
		db.rollback()
		workflows = []
	items: list[dict[str, Any]] = []
	for workflow in workflows:
		data = workflow.workflow_data or {}
		nodes = data.get("nodes") or []
		for node in nodes:
			if not isinstance(node, dict) or node.get("type") != "trigger":
				continue
			cfg = node.get("config") or {}
			if not isinstance(cfg, dict) or cfg.get("trigger_type") != "scheduled":
				continue
			cron = resolve_schedule_config_to_cron(cfg)
			items.append(
				{
					"kind": "workflow",
					"id": workflow.id,
					"business_id": workflow.business_id,
					"name": workflow.name,
					"cron": cron,
					"timezone": cfg.get("timezone") or "Asia/Tehran",
					"enabled": True,
				}
			)
			break
	return {"ai_eval": ai_eval, "workflows": items}


def storage_usage_report(db: Session, limit: int = 30) -> dict[str, Any]:
	rows = (
		db.query(
			FileStorage.business_id,
			func.count(FileStorage.id),
			func.coalesce(func.sum(FileStorage.file_size), 0),
		)
		.filter(FileStorage.deleted_at.is_(None), FileStorage.is_active.is_(True))
		.group_by(FileStorage.business_id)
		.order_by(func.sum(FileStorage.file_size).desc())
		.limit(limit)
		.all()
	)
	business_ids = [row[0] for row in rows if row[0] is not None]
	names = {}
	if business_ids:
		for business in db.query(Business).filter(Business.id.in_(business_ids)).all():
			names[business.id] = business.name
	total_bytes = int(
		db.query(func.coalesce(func.sum(FileStorage.file_size), 0))
		.filter(FileStorage.deleted_at.is_(None), FileStorage.is_active.is_(True))
		.scalar()
		or 0
	)
	return {
		"total_bytes": total_bytes,
		"items": [
			{
				"business_id": row[0],
				"business_name": names.get(row[0]) if row[0] is not None else None,
				"files": int(row[1] or 0),
				"bytes": int(row[2] or 0),
			}
			for row in rows
		],
	}


def inactive_businesses_report(db: Session, days: int = 90, limit: int = 50) -> dict[str, Any]:
	cutoff = datetime.utcnow() - timedelta(days=days)
	rows = (
		db.query(Business)
		.filter(Business.deleted_at.is_(None), Business.updated_at < cutoff)
		.order_by(Business.updated_at.asc())
		.limit(limit)
		.all()
	)
	return {
		"days": days,
		"items": [
			{
				"id": row.id,
				"name": row.name,
				"owner_id": row.owner_id,
				"updated_at": row.updated_at.isoformat() if row.updated_at else None,
			}
			for row in rows
		],
	}


def failed_login_report(db: Session, hours: int = 24, limit: int = 80) -> dict[str, Any]:
	report = get_auth_security_report(db, hours=hours, limit=limit)
	by_type = report.get("by_type") or {}
	recent = [
		item
		for item in (report.get("recent") or [])
		if "fail" in str(item.get("event_type") or "").lower()
		or str(item.get("event_type") or "") in _FAIL_EVENTS
	]
	return {
		"period_hours": hours,
		"by_type": {
			key: count
			for key, count in by_type.items()
			if "fail" in str(key).lower() or str(key) in _FAIL_EVENTS
		},
		"recent": recent,
	}


def expiring_licenses(db: Session, within_days: int = 30, limit: int = 100) -> dict[str, Any]:
	now = datetime.utcnow()
	horizon = now + timedelta(days=within_days)
	recent_floor = now - timedelta(days=within_days)
	rows = (
		db.query(BusinessPlugin, MarketplacePlugin, Business)
		.join(MarketplacePlugin, MarketplacePlugin.id == BusinessPlugin.plugin_id)
		.join(Business, Business.id == BusinessPlugin.business_id)
		.filter(
			BusinessPlugin.ends_at.isnot(None),
			BusinessPlugin.ends_at <= horizon,
			BusinessPlugin.status.in_(("active", "expired")),
			or_(
				BusinessPlugin.ends_at >= recent_floor,
				BusinessPlugin.status == "active",
			),
		)
		.order_by(BusinessPlugin.ends_at.asc())
		.limit(limit)
		.all()
	)
	return {
		"within_days": within_days,
		"items": [
			{
				"license_id": license_row.id,
				"business_id": business.id,
				"business_name": business.name,
				"plugin_code": plugin.code,
				"plugin_name": getattr(plugin, "name", None) or plugin.code,
				"status": license_row.status,
				"ends_at": license_row.ends_at.isoformat() if license_row.ends_at else None,
				"is_trial": license_row.is_trial,
				"expired": bool(license_row.ends_at and license_row.ends_at < now),
			}
			for license_row, plugin, business in rows
		],
	}
