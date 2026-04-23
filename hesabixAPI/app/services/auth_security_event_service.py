from __future__ import annotations

import hashlib
import json
import logging
from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import select, func
from sqlalchemy.orm import Session

from adapters.db.models.auth_security_event import AuthSecurityEvent
from adapters.db.session import get_db_session
from app.core.responses import ApiError
from app.core.settings import get_settings

logger = logging.getLogger(__name__)


def _account_key_for_login(*, ip: str | None, identifier: str) -> str:
	secret = get_settings().captcha_secret
	raw = f"{secret}:{ip or ''}:{identifier.strip().lower()}"
	return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:32]


def log_auth_security_event(
	*,
	event_type: str,
	client_ip: str | None = None,
	account_key: str | None = None,
	detail: dict[str, Any] | None = None,
) -> None:
	"""ثبت رویداد در تراکنش جدا تا با rollback درخواست از بین نرود."""
	try:
		with get_db_session() as db:
			row = AuthSecurityEvent(
				event_type=event_type,
				client_ip=(client_ip[:45] if client_ip else None),
				account_key=account_key,
				detail_json=json.dumps(detail, ensure_ascii=False) if detail else None,
			)
			db.add(row)
			db.commit()
	except Exception as e:
		logger.warning("auth_security_event log failed: %s", e)


def check_login_backoff(
	db: Session,
	*,
	client_ip: str | None,
	identifier: str,
	max_fails: int,
	window_minutes: int,
	backoff_seconds: int,
) -> None:
	"""اگر تعداد تلاش‌های ناموفق در پنجره به حد برسد، ۴۲۹."""
	if max_fails <= 0 or window_minutes <= 0 or backoff_seconds < 0:
		return
	ak = _account_key_for_login(ip=client_ip, identifier=identifier)
	since = datetime.utcnow() - timedelta(minutes=window_minutes)
	q = (
		select(func.count())
		.select_from(AuthSecurityEvent)
		.where(
			AuthSecurityEvent.event_type == "login_password_failed",
			AuthSecurityEvent.account_key == ak,
			AuthSecurityEvent.created_at >= since,
		)
	)
	n = int(db.execute(q).scalar() or 0)
	if n < max_fails:
		return
	raise ApiError(
		"LOGIN_BACKOFF",
		f"به‌دلیل تلاش‌های ناموفق متعدد، لطفاً {backoff_seconds} ثانیه صبر کنید و دوباره تلاش کنید.",
		http_status=429,
		details={"retry_after_seconds": backoff_seconds} if backoff_seconds else None,
	)


def record_login_password_failed(
	*,
	client_ip: str | None,
	identifier: str,
) -> None:
	ak = _account_key_for_login(ip=client_ip, identifier=identifier)
	log_auth_security_event(
		event_type="login_password_failed",
		client_ip=client_ip,
		account_key=ak,
		detail={"kind": "bad_password_or_user"},
	)


def get_auth_security_report(
	db: Session,
	*,
	hours: int = 24,
	limit: int = 100,
) -> dict[str, Any]:
	"""خلاصه و آخرین رویدادها برای پنل مدیر."""
	if hours < 1:
		hours = 1
	if hours > 24 * 90:
		hours = 24 * 90
	if limit < 1:
		limit = 1
	if limit > 500:
		limit = 500
	since = datetime.utcnow() - timedelta(hours=hours)

	type_q = (
		select(AuthSecurityEvent.event_type, func.count().label("c"))
		.where(AuthSecurityEvent.created_at >= since)
		.group_by(AuthSecurityEvent.event_type)
	)
	by_type: dict[str, int] = {}
	for row in db.execute(type_q).all():
		by_type[str(row[0])] = int(row[1])

	total_q = select(func.count()).select_from(AuthSecurityEvent).where(AuthSecurityEvent.created_at >= since)
	total = int(db.execute(total_q).scalar() or 0)

	recent_q = (
		select(AuthSecurityEvent)
		.where(AuthSecurityEvent.created_at >= since)
		.order_by(AuthSecurityEvent.created_at.desc())
		.limit(limit)
	)
	recent: list[dict[str, Any]] = []
	for ev in db.execute(recent_q).scalars().all():
		recent.append(
			{
				"id": ev.id,
				"created_at": ev.created_at.isoformat() if ev.created_at else None,
				"event_type": ev.event_type,
				"client_ip": ev.client_ip,
				"detail": json.loads(ev.detail_json) if ev.detail_json else None,
			}
		)

	return {
		"period_hours": hours,
		"total": total,
		"by_type": by_type,
		"recent": recent,
	}
