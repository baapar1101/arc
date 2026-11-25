"""ثبت و فهرست لاگ کارهای مدیر سیستم."""

from __future__ import annotations

import json
import logging
from typing import Any

from fastapi import Request
from sqlalchemy import desc
from sqlalchemy.orm import Session

from adapters.db.models.admin_audit_log import AdminAuditLog
from adapters.db.models.user import User

logger = logging.getLogger(__name__)


def client_ip_from_request(request: Request | None) -> str | None:
	if request is None:
		return None
	forwarded = request.headers.get("x-forwarded-for")
	if forwarded:
		return forwarded.split(",")[0].strip()[:64] or None
	if request.client and request.client.host:
		return str(request.client.host)[:64]
	return None


def record_admin_action(
	db: Session,
	*,
	actor_user_id: int | None,
	action: str,
	summary: str,
	target_type: str | None = None,
	target_id: str | None = None,
	metadata: dict[str, Any] | None = None,
	client_ip: str | None = None,
	commit: bool = True,
) -> None:
	"""ثبت یک رویداد. خطای لاگ کار اصلی را برنمی‌گرداند."""
	try:
		row = AdminAuditLog(
			actor_user_id=actor_user_id,
			action=action[:64],
			target_type=(target_type or None),
			target_id=(str(target_id)[:64] if target_id is not None else None),
			summary=summary[:500],
			metadata_json=json.dumps(metadata, ensure_ascii=False, default=str) if metadata else None,
			client_ip=client_ip,
		)
		with db.begin_nested():
			db.add(row)
		if commit:
			db.commit()
		else:
			db.flush()
	except Exception:
		logger.exception("admin_audit_record_failed", extra={"action": action})
		if commit:
			try:
				db.commit()
			except Exception:
				logger.exception("admin_audit_commit_failed", extra={"action": action})


def list_admin_actions(
	db: Session,
	*,
	action: str | None = None,
	skip: int = 0,
	take: int = 50,
) -> dict[str, Any]:
	query = db.query(AdminAuditLog)
	if action:
		query = query.filter(AdminAuditLog.action == action)
	total = query.count()
	rows = (
		query.order_by(desc(AdminAuditLog.created_at), desc(AdminAuditLog.id))
		.offset(skip)
		.limit(take)
		.all()
	)
	actor_ids = {row.actor_user_id for row in rows if row.actor_user_id}
	names: dict[int, str] = {}
	if actor_ids:
		for user in db.query(User).filter(User.id.in_(actor_ids)).all():
			label = " ".join(
				part for part in (user.first_name or "", user.last_name or "") if part
			).strip()
			names[user.id] = label or user.email or user.mobile or str(user.id)
	items = []
	for row in rows:
		meta = None
		if row.metadata_json:
			try:
				meta = json.loads(row.metadata_json)
			except Exception:
				meta = {"raw": row.metadata_json}
		items.append(
			{
				"id": row.id,
				"created_at": row.created_at.isoformat() if row.created_at else None,
				"actor_user_id": row.actor_user_id,
				"actor_name": names.get(row.actor_user_id or 0),
				"action": row.action,
				"target_type": row.target_type,
				"target_id": row.target_id,
				"summary": row.summary,
				"metadata": meta,
				"client_ip": row.client_ip,
			}
		)
	return {"total": total, "items": items}
