"""گزارش‌های افزونه تلفن."""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

from adapters.db.models.telephony import TelephonyCall
from adapters.db.models.user import User


def _parse_range(
	date_from: Optional[str], date_to: Optional[str]
) -> tuple[datetime, datetime]:
	now = datetime.utcnow()
	end = now
	start = now - timedelta(days=7)
	if date_from:
		try:
			start = datetime.fromisoformat(date_from.replace("Z", ""))
		except Exception:
			pass
	if date_to:
		try:
			end = datetime.fromisoformat(date_to.replace("Z", ""))
		except Exception:
			pass
	return start, end


def summary_report(
	db: Session,
	business_id: int,
	*,
	date_from: Optional[str] = None,
	date_to: Optional[str] = None,
) -> Dict[str, Any]:
	start, end = _parse_range(date_from, date_to)
	base = db.query(TelephonyCall).filter(
		TelephonyCall.business_id == business_id,
		TelephonyCall.started_at >= start,
		TelephonyCall.started_at <= end,
	)
	total = base.count()
	inbound = base.filter(TelephonyCall.direction == "inbound").count()
	outbound = base.filter(TelephonyCall.direction == "outbound").count()
	answered = base.filter(TelephonyCall.status.in_(["answered", "completed"])).count()
	missed = base.filter(TelephonyCall.status == "missed").count()
	busy = base.filter(TelephonyCall.status == "busy").count()
	failed = base.filter(TelephonyCall.status == "failed").count()
	avg_duration = (
		db.query(func.avg(TelephonyCall.talk_sec))
		.filter(
			TelephonyCall.business_id == business_id,
			TelephonyCall.started_at >= start,
			TelephonyCall.started_at <= end,
			TelephonyCall.talk_sec.isnot(None),
		)
		.scalar()
	)
	avg_ring = None
	answered_calls = (
		db.query(TelephonyCall)
		.filter(
			TelephonyCall.business_id == business_id,
			TelephonyCall.started_at >= start,
			TelephonyCall.started_at <= end,
			TelephonyCall.answered_at.isnot(None),
			TelephonyCall.started_at.isnot(None),
		)
		.limit(5000)
		.all()
	)
	if answered_calls:
		rings = [
			max(0, int((c.answered_at - c.started_at).total_seconds()))
			for c in answered_calls
			if c.answered_at and c.started_at
		]
		if rings:
			avg_ring = sum(rings) / len(rings)
	# hourly histogram (UTC)
	rows = (
		db.query(func.extract("hour", TelephonyCall.started_at), func.count(TelephonyCall.id))
		.filter(
			TelephonyCall.business_id == business_id,
			TelephonyCall.started_at >= start,
			TelephonyCall.started_at <= end,
		)
		.group_by(func.extract("hour", TelephonyCall.started_at))
		.all()
	)
	by_hour = {int(h or 0): int(c) for h, c in rows}
	hourly = [{"hour": h, "count": by_hour.get(h, 0)} for h in range(24)]
	return {
		"range": {"from": start.isoformat(), "to": end.isoformat()},
		"totals": {
			"all": total,
			"inbound": inbound,
			"outbound": outbound,
			"answered": answered,
			"missed": missed,
			"busy": busy,
			"failed": failed,
			"answer_rate": round((answered / inbound) * 100, 1) if inbound else 0.0,
			"avg_talk_sec": round(float(avg_duration or 0), 1),
			"avg_ring_sec": round(float(avg_ring or 0), 1) if avg_ring is not None else None,
		},
		"hourly": hourly,
	}


def operators_report(
	db: Session,
	business_id: int,
	*,
	date_from: Optional[str] = None,
	date_to: Optional[str] = None,
) -> Dict[str, Any]:
	start, end = _parse_range(date_from, date_to)
	agg: Dict[int, Dict[str, Any]] = {}
	calls = (
		db.query(TelephonyCall)
		.filter(
			TelephonyCall.business_id == business_id,
			TelephonyCall.started_at >= start,
			TelephonyCall.started_at <= end,
			TelephonyCall.assigned_user_id.isnot(None),
		)
		.all()
	)
	for c in calls:
		uid = int(c.assigned_user_id)
		slot = agg.setdefault(
			uid,
			{"user_id": uid, "total": 0, "answered": 0, "missed": 0, "outbound": 0, "talk_sec": 0},
		)
		slot["total"] += 1
		if c.status in ("answered", "completed"):
			slot["answered"] += 1
		if c.status == "missed":
			slot["missed"] += 1
		if c.direction == "outbound":
			slot["outbound"] += 1
		slot["talk_sec"] += int(c.talk_sec or 0)

	user_ids = list(agg.keys())
	users = {u.id: u for u in db.query(User).filter(User.id.in_(user_ids)).all()} if user_ids else {}
	items: List[Dict[str, Any]] = []
	for uid, slot in agg.items():
		u = users.get(uid)
		name = f"{getattr(u, 'first_name', '') or ''} {getattr(u, 'last_name', '') or ''}".strip() if u else f"#{uid}"
		if not name:
			name = getattr(u, "mobile", None) or f"#{uid}"
		items.append(
			{
				**slot,
				"user_name": name,
				"avg_talk_sec": round(slot["talk_sec"] / slot["answered"], 1) if slot["answered"] else 0,
			}
		)
	items.sort(key=lambda x: x["total"], reverse=True)
	return {"range": {"from": start.isoformat(), "to": end.isoformat()}, "items": items}


def by_person_report(
	db: Session,
	business_id: int,
	*,
	date_from: Optional[str] = None,
	date_to: Optional[str] = None,
	limit: int = 50,
) -> Dict[str, Any]:
	start, end = _parse_range(date_from, date_to)
	rows = (
		db.query(
			TelephonyCall.person_id,
			func.count(TelephonyCall.id).label("cnt"),
			func.sum(func.coalesce(TelephonyCall.talk_sec, 0)).label("talk"),
		)
		.filter(
			TelephonyCall.business_id == business_id,
			TelephonyCall.started_at >= start,
			TelephonyCall.started_at <= end,
			TelephonyCall.person_id.isnot(None),
		)
		.group_by(TelephonyCall.person_id)
		.order_by(func.count(TelephonyCall.id).desc())
		.limit(min(limit, 200))
		.all()
	)
	from adapters.db.models.person import Person

	person_ids = [r[0] for r in rows]
	persons = {
		p.id: p for p in db.query(Person).filter(Person.id.in_(person_ids)).all()
	} if person_ids else {}
	items = []
	for pid, cnt, talk in rows:
		p = persons.get(pid)
		name = None
		if p:
			name = (p.alias_name or "").strip() or f"{p.first_name or ''} {p.last_name or ''}".strip() or p.company_name
		items.append(
			{
				"person_id": pid,
				"person_name": name or f"#{pid}",
				"calls": int(cnt),
				"talk_sec": int(talk or 0),
			}
		)
	return {"range": {"from": start.isoformat(), "to": end.isoformat()}, "items": items}


def by_extension_report(
	db: Session,
	business_id: int,
	*,
	date_from: Optional[str] = None,
	date_to: Optional[str] = None,
) -> Dict[str, Any]:
	start, end = _parse_range(date_from, date_to)
	rows = (
		db.query(
			TelephonyCall.extension,
			func.count(TelephonyCall.id),
			func.sum(func.coalesce(TelephonyCall.talk_sec, 0)),
		)
		.filter(
			TelephonyCall.business_id == business_id,
			TelephonyCall.started_at >= start,
			TelephonyCall.started_at <= end,
			TelephonyCall.extension.isnot(None),
		)
		.group_by(TelephonyCall.extension)
		.order_by(func.count(TelephonyCall.id).desc())
		.all()
	)
	items = [
		{"extension": ext, "calls": int(cnt), "talk_sec": int(talk or 0)}
		for ext, cnt, talk in rows
	]
	return {"range": {"from": start.isoformat(), "to": end.isoformat()}, "items": items}
