from __future__ import annotations

import ipaddress
import json
import logging
import os
import time
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Literal, Optional, Sequence, Tuple

from sqlalchemy import Date, and_, cast, desc, func, or_
from sqlalchemy.orm import Session

from adapters.db.models.firewall_rule import FirewallAuditLog, FirewallRequestLog, FirewallRule
from adapters.db.session import get_db_session

logger = logging.getLogger(__name__)

CACHE_TTL_SEC = 8.0
_rules_cache: dict[str, Any] = {"compiled": [], "loaded_at": 0.0}


@dataclass(frozen=True)
class _CompiledRule:
	rule_id: int
	action: str
	network: ipaddress._BaseNetwork
	path_prefix: Optional[str]
	methods: Optional[frozenset[str]]
	priority: int


def is_firewall_globally_disabled() -> bool:
	v = os.getenv("HESABIX_FIREWALL_DISABLED", "").strip().lower()
	return v in {"1", "true", "yes", "on"}


def invalidate_rules_cache() -> None:
	_rules_cache["loaded_at"] = 0.0


def should_refresh_rules_cache() -> bool:
	return (time.monotonic() - float(_rules_cache["loaded_at"])) > CACHE_TTL_SEC


def _parse_methods(raw: Optional[str]) -> Optional[frozenset[str]]:
	if not raw or not raw.strip():
		return None
	parts = [p.strip().upper() for p in raw.split(",") if p.strip()]
	if not parts or parts == ["*"]:
		return None
	return frozenset(parts)


def _compile_rule(row: FirewallRule) -> Optional[_CompiledRule]:
	try:
		net = ipaddress.ip_network(row.ip_cidr.strip(), strict=False)
	except ValueError:
		logger.warning("firewall: invalid ip_cidr on rule id=%s value=%r", row.id, row.ip_cidr)
		return None
	path_prefix = (row.path_prefix or "").strip() or None
	if path_prefix and not path_prefix.startswith("/"):
		path_prefix = "/" + path_prefix
	return _CompiledRule(
		rule_id=int(row.id),
		action=row.action,
		network=net,
		path_prefix=path_prefix,
		methods=_parse_methods(row.http_methods),
		priority=int(row.priority),
	)


def _load_active_rules(db: Session) -> list[_CompiledRule]:
	now = datetime.utcnow()
	q = (
		db.query(FirewallRule)
		.filter(FirewallRule.enabled.is_(True))
		.filter(or_(FirewallRule.expires_at.is_(None), FirewallRule.expires_at > now))
		.order_by(FirewallRule.priority.asc(), FirewallRule.id.asc())
	)
	compiled: list[_CompiledRule] = []
	for row in q.all():
		c = _compile_rule(row)
		if c:
			compiled.append(c)
	return compiled


def refresh_rules_cache_sync() -> None:
	from adapters.db.session import SessionLocal

	db = SessionLocal()
	try:
		compiled = _load_active_rules(db)
		_rules_cache["compiled"] = compiled
		_rules_cache["loaded_at"] = time.monotonic()
	finally:
		db.close()


def evaluate_request(client_ip: str, path: str, method: str) -> Tuple[Literal["allow", "deny", "pass"], Optional[int]]:
	"""
	ارزیابی قوانین فعال.
	اولین قانون هم‌خوان بر اساس اولویت تعیین‌کننده است.
	اگر هیچ قانونی نخورد: pass (اجازه).
	"""
	try:
		addr = ipaddress.ip_address(client_ip.split("%")[0].strip())
	except ValueError:
		addr = None

	if addr is None:
		return "pass", None

	method_u = (method or "GET").upper()
	compiled: Sequence[_CompiledRule] = _rules_cache.get("compiled") or []

	for rule in compiled:
		if addr not in rule.network:
			continue
		if rule.path_prefix and not path.startswith(rule.path_prefix):
			continue
		if rule.methods is not None and method_u not in rule.methods:
			continue
		decision: Literal["allow", "deny"] = "allow" if rule.action == "allow" else "deny"
		return decision, rule.rule_id

	return "pass", None


def should_skip_firewall_path(path: str) -> bool:
	if path in ("/", "/health", "/api/v1/health"):
		return True
	if path.startswith("/docs") or path.startswith("/redoc") or path.startswith("/openapi.json") or path.startswith("/assets"):
		return True
	# مدیریت فایروال باید حتی وقتی IP در لیست رد است در دسترس باشد (با توکن معتبر)
	if path.startswith("/api/v1/admin/firewall"):
		return True
	return False


def log_blocked_request_sync(
	client_ip: str,
	path: str,
	method: str,
	user_agent: Optional[str],
	rule_id: Optional[int],
) -> None:
	try:
		with get_db_session() as db:
			db.add(
				FirewallRequestLog(
					client_ip=client_ip[:45],
					method=(method or "")[:16],
					path=path[:1024],
					user_agent=(user_agent or "")[:512] if user_agent else None,
					rule_id=rule_id,
				)
			)
	except Exception as e:
		logger.warning("firewall: failed to write request log: %s", e)


def _write_audit(
	db: Session,
	event_type: str,
	actor_user_id: Optional[int],
	ip_cidr: Optional[str],
	rule_id: Optional[int],
	details: Optional[dict],
) -> None:
	db.add(
		FirewallAuditLog(
			event_type=event_type,
			actor_user_id=actor_user_id,
			ip_cidr=ip_cidr,
			rule_id=rule_id,
			details=json.dumps(details, ensure_ascii=False) if details else None,
		)
	)


def validate_ip_or_cidr(value: str) -> str:
	v = value.strip()
	ipaddress.ip_network(v, strict=False)
	return v


def list_rules(db: Session) -> list[dict]:
	q = db.query(FirewallRule).order_by(FirewallRule.priority.asc(), FirewallRule.id.asc())
	return [rule_to_dict(r) for r in q.all()]


def rule_to_dict(r: FirewallRule) -> dict:
	return {
		"id": r.id,
		"enabled": r.enabled,
		"action": r.action,
		"ip_cidr": r.ip_cidr,
		"path_prefix": r.path_prefix,
		"http_methods": r.http_methods,
		"priority": r.priority,
		"expires_at": r.expires_at.isoformat() if r.expires_at else None,
		"note": r.note,
		"source": r.source,
		"created_by_user_id": r.created_by_user_id,
		"created_at": r.created_at.isoformat() if r.created_at else None,
		"updated_at": r.updated_at.isoformat() if r.updated_at else None,
	}


def create_rule(
	db: Session,
	*,
	action: str,
	ip_cidr: str,
	path_prefix: Optional[str],
	http_methods: Optional[str],
	priority: int,
	expires_at: Optional[datetime],
	note: Optional[str],
	source: str,
	created_by_user_id: Optional[int],
) -> FirewallRule:
	ip_cidr = validate_ip_or_cidr(ip_cidr)
	if action not in ("allow", "deny"):
		raise ValueError("action must be allow or deny")
	now = datetime.utcnow()
	row = FirewallRule(
		enabled=True,
		action=action,
		ip_cidr=ip_cidr,
		path_prefix=path_prefix.strip() if path_prefix else None,
		http_methods=http_methods.strip() if http_methods else None,
		priority=priority,
		expires_at=expires_at,
		note=note,
		source=source[:32],
		created_by_user_id=created_by_user_id,
		created_at=now,
		updated_at=now,
	)
	db.add(row)
	db.flush()
	_write_audit(db, "rule_create", created_by_user_id, ip_cidr, row.id, {"action": action})
	return row


def update_rule(
	db: Session,
	rule_id: int,
	*,
	enabled: Optional[bool] = None,
	action: Optional[str] = None,
	ip_cidr: Optional[str] = None,
	path_prefix: Optional[str] = None,
	http_methods: Optional[str] = None,
	priority: Optional[int] = None,
	expires_at: Optional[datetime] = None,
	note: Optional[str] = None,
	actor_user_id: Optional[int] = None,
) -> Optional[FirewallRule]:
	row = db.get(FirewallRule, rule_id)
	if not row:
		return None
	if action is not None:
		if action not in ("allow", "deny"):
			raise ValueError("action must be allow or deny")
		row.action = action
	if ip_cidr is not None:
		row.ip_cidr = validate_ip_or_cidr(ip_cidr)
	if path_prefix is not None:
		row.path_prefix = path_prefix.strip() if path_prefix.strip() else None
	if http_methods is not None:
		row.http_methods = http_methods.strip() if http_methods.strip() else None
	if priority is not None:
		row.priority = priority
	if expires_at is not None:
		row.expires_at = expires_at
	if note is not None:
		row.note = note
	if enabled is not None:
		row.enabled = enabled
	row.updated_at = datetime.utcnow()
	_write_audit(db, "rule_update", actor_user_id, row.ip_cidr, row.id, None)
	return row


def delete_rule(db: Session, rule_id: int, actor_user_id: Optional[int]) -> bool:
	row = db.get(FirewallRule, rule_id)
	if not row:
		return False
	ip = row.ip_cidr
	db.delete(row)
	_write_audit(db, "rule_delete", actor_user_id, ip, rule_id, None)
	return True


def ban_ip(
	db: Session,
	ip: str,
	*,
	duration_seconds: Optional[int],
	note: str,
	path_prefix: Optional[str],
	http_methods: Optional[str],
	priority: int,
	created_by_user_id: Optional[int],
	source: str = "api_ban",
) -> FirewallRule:
	"""برای فراخوانی از سایر بخش‌های برنامه: افزودن قانون رد موقت یا دائم."""
	ip_norm = validate_ip_or_cidr(ip)
	expires_at: Optional[datetime] = None
	if duration_seconds is not None and duration_seconds > 0:
		expires_at = datetime.utcnow() + timedelta(seconds=int(duration_seconds))
	return create_rule(
		db,
		action="deny",
		ip_cidr=ip_norm,
		path_prefix=path_prefix,
		http_methods=http_methods,
		priority=priority,
		expires_at=expires_at,
		note=note,
		source=source,
		created_by_user_id=created_by_user_id,
	)


def unban_ip(
	db: Session,
	ip: str,
	*,
	actor_user_id: Optional[int],
	only_source: Optional[str] = None,
) -> int:
	"""حذف/غیرفعال‌سازی قوانین رد فعال برای این IP (یا CIDR)."""
	ip_norm = validate_ip_or_cidr(ip)
	q = db.query(FirewallRule).filter(
		FirewallRule.action == "deny",
		FirewallRule.ip_cidr == ip_norm,
		FirewallRule.enabled.is_(True),
	)
	if only_source:
		q = q.filter(FirewallRule.source == only_source)
	rows = q.all()
	count = 0
	for row in rows:
		_write_audit(db, "unban", actor_user_id, ip_norm, row.id, {"source": row.source})
		db.delete(row)
		count += 1
	return count


def has_active_login_fail_auto_ban(db: Session, client_ip: str) -> bool:
	"""اگر برای این IP قبلاً قانون رد فعال با منبع ورود ناموفق ثبت شده باشد."""
	raw = (client_ip or "").strip().split("%")[0].strip()
	if not raw or raw == "unknown":
		return False
	try:
		ip_norm = validate_ip_or_cidr(raw)
	except ValueError:
		ip_norm = raw
	now = datetime.utcnow()
	row = (
		db.query(FirewallRule)
		.filter(
			FirewallRule.enabled.is_(True),
			FirewallRule.action == "deny",
			FirewallRule.ip_cidr == ip_norm,
			FirewallRule.source == "login_fail_auto",
			or_(FirewallRule.expires_at.is_(None), FirewallRule.expires_at > now),
		)
		.first()
	)
	return row is not None


def list_request_logs(
	db: Session,
	*,
	skip: int = 0,
	limit: int = 50,
	client_ip: Optional[str] = None,
	since: Optional[datetime] = None,
	until: Optional[datetime] = None,
) -> tuple[list[dict], int]:
	q = db.query(FirewallRequestLog)
	if client_ip:
		q = q.filter(FirewallRequestLog.client_ip == client_ip.strip())
	if since:
		q = q.filter(FirewallRequestLog.created_at >= since)
	if until:
		q = q.filter(FirewallRequestLog.created_at <= until)
	total = q.count()
	rows = q.order_by(desc(FirewallRequestLog.created_at)).offset(skip).limit(min(limit, 200)).all()
	items = [
		{
			"id": r.id,
			"created_at": r.created_at.isoformat() if r.created_at else None,
			"client_ip": r.client_ip,
			"method": r.method,
			"path": r.path,
			"user_agent": r.user_agent,
			"rule_id": r.rule_id,
		}
		for r in rows
	]
	return items, total


def list_audit_logs(
	db: Session,
	*,
	skip: int = 0,
	limit: int = 50,
	since: Optional[datetime] = None,
) -> tuple[list[dict], int]:
	q = db.query(FirewallAuditLog)
	if since:
		q = q.filter(FirewallAuditLog.created_at >= since)
	total = q.count()
	rows = q.order_by(desc(FirewallAuditLog.created_at)).offset(skip).limit(min(limit, 200)).all()
	items = []
	for r in rows:
		details = None
		if r.details:
			try:
				details = json.loads(r.details)
			except json.JSONDecodeError:
				details = r.details
		items.append(
			{
				"id": r.id,
				"created_at": r.created_at.isoformat() if r.created_at else None,
				"event_type": r.event_type,
				"actor_user_id": r.actor_user_id,
				"ip_cidr": r.ip_cidr,
				"rule_id": r.rule_id,
				"details": details,
			}
		)
	return items, total


def reports_summary(db: Session, *, days: int = 7) -> dict:
	days = max(1, min(int(days), 90))
	since = datetime.utcnow() - timedelta(days=days)
	base = db.query(FirewallRequestLog).filter(FirewallRequestLog.created_at >= since)
	total_blocks = base.count()
	by_ip_rows = (
		db.query(FirewallRequestLog.client_ip, func.count(FirewallRequestLog.id))
		.filter(FirewallRequestLog.created_at >= since)
		.group_by(FirewallRequestLog.client_ip)
		.order_by(desc(func.count(FirewallRequestLog.id)))
		.limit(20)
		.all()
	)
	top_ips = [{"client_ip": ip, "count": int(cnt)} for ip, cnt in by_ip_rows]
	day_col = cast(FirewallRequestLog.created_at, Date)
	day_rows = (
		db.query(day_col, func.count(FirewallRequestLog.id))
		.filter(FirewallRequestLog.created_at >= since)
		.group_by(day_col)
		.order_by(day_col)
		.all()
	)
	# PostgreSQL date might be returned as date object
	blocks_by_day = []
	for d, cnt in day_rows:
		ds = d.isoformat() if hasattr(d, "isoformat") else str(d)
		blocks_by_day.append({"date": ds, "count": int(cnt)})
	active_deny = (
		db.query(func.count(FirewallRule.id))
		.filter(
			and_(
				FirewallRule.enabled.is_(True),
				FirewallRule.action == "deny",
				or_(FirewallRule.expires_at.is_(None), FirewallRule.expires_at > datetime.utcnow()),
			)
		)
		.scalar()
	)
	return {
		"period_days": days,
		"total_blocked_requests": total_blocks,
		"top_blocked_ips": top_ips,
		"blocks_by_day": blocks_by_day,
		"active_deny_rules": int(active_deny or 0),
	}
