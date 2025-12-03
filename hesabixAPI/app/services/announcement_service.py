from __future__ import annotations

from datetime import datetime
import re
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy.orm import Session
from sqlalchemy import and_, or_, func

from adapters.db.models.announcement import Announcement, UserAnnouncement


def _paginate(query, page: int, limit: int) -> Tuple[List[Any], int, int, int]:
	"""Helper: apply pagination and return (items, total, page, total_pages)."""
	if page <= 0:
		page = 1
	if limit <= 0:
		limit = 10
	total = query.count()
	total_pages = (total + limit - 1) // limit if limit > 0 else 1
	offset = (page - 1) * limit
	items = query.offset(offset).limit(limit).all()
	return items, total, page, total_pages


# ========== Admin ==========
def admin_list(db: Session, page: int, limit: int, level: Optional[str] = None, active: Optional[bool] = None) -> Dict[str, Any]:
	q = db.query(Announcement)
	if level:
		q = q.filter(Announcement.level == level)
	if active is not None:
		q = q.filter(Announcement.is_active == bool(active))
	q = q.order_by(Announcement.is_pinned.desc(), Announcement.updated_at.desc())
	items, total, page, total_pages = _paginate(q, page, limit)
	return {
		"items": [_to_dict(a) for a in items],
		"total": total,
		"page": page,
		"limit": limit,
		"total_pages": total_pages,
	}


def admin_create(db: Session, payload: Dict[str, Any], created_by: Optional[int]) -> Dict[str, Any]:
	a = Announcement(
		title=str(payload.get("title") or "").strip(),
		body=str(payload.get("body") or "").strip(),
		level=str(payload.get("level") or "info"),
		is_pinned=bool(payload.get("is_pinned") or False),
		is_active=bool(payload.get("is_active") or False),
		starts_at=_parse_dt(payload.get("starts_at")),
		ends_at=_parse_dt(payload.get("ends_at")),
		audience_filters=payload.get("audience_filters"),
		created_by=created_by,
	)
	db.add(a)
	db.commit()
	db.refresh(a)
	return _to_dict(a)


def admin_update(db: Session, ann_id: int, payload: Dict[str, Any]) -> Optional[Dict[str, Any]]:
	a = db.query(Announcement).filter(Announcement.id == int(ann_id)).first()
	if not a:
		return None
	if "title" in payload:
		a.title = str(payload.get("title") or "").strip()
	if "body" in payload:
		a.body = str(payload.get("body") or "").strip()
	if "level" in payload:
		a.level = str(payload.get("level") or "info")
	if "is_pinned" in payload:
		a.is_pinned = bool(payload.get("is_pinned"))
	if "is_active" in payload:
		a.is_active = bool(payload.get("is_active"))
	if "starts_at" in payload:
		a.starts_at = _parse_dt(payload.get("starts_at"))
	if "ends_at" in payload:
		a.ends_at = _parse_dt(payload.get("ends_at"))
	if "audience_filters" in payload:
		a.audience_filters = payload.get("audience_filters")
	db.commit()
	db.refresh(a)
	return _to_dict(a)


def admin_delete(db: Session, ann_id: int) -> bool:
	a = db.query(Announcement).filter(Announcement.id == int(ann_id)).first()
	if not a:
		return False
	db.delete(a)
	db.commit()
	return True


def admin_publish(db: Session, ann_id: int, active: bool, is_pinned: Optional[bool] = None) -> Optional[Dict[str, Any]]:
	a = db.query(Announcement).filter(Announcement.id == int(ann_id)).first()
	if not a:
		return None
	a.is_active = bool(active)
	if is_pinned is not None:
		a.is_pinned = bool(is_pinned)
	db.commit()
	db.refresh(a)
	return _to_dict(a)


# ========== User ==========
def user_list(
	db: Session,
	user_id: int,
	page: int,
	limit: int,
	level: Optional[str] = None,
	only_unread: bool = False,
	locale: Optional[str] = None,
) -> Dict[str, Any]:
	now = datetime.utcnow()
	q = db.query(Announcement, UserAnnouncement).outerjoin(
		UserAnnouncement,
		and_(
			UserAnnouncement.announcement_id == Announcement.id,
			UserAnnouncement.user_id == int(user_id),
		)
	).filter(
		Announcement.is_active == True,
		or_(Announcement.starts_at == None, Announcement.starts_at <= now),
		or_(Announcement.ends_at == None, Announcement.ends_at >= now),
	)
	if level:
		q = q.filter(Announcement.level == level)
	if only_unread:
		# فقط اعلان‌هایی که نه خوانده شده‌اند و نه پنهان شده‌اند
		# یا اصلاً در UserAnnouncement نیستند (یعنی خوانده نشده‌اند) یا اگر هستند، read_at و dismissed_at باید None باشند
		q = q.filter(
			or_(
				UserAnnouncement.id == None,  # اعلان‌هایی که اصلاً در UserAnnouncement نیستند
				and_(
					UserAnnouncement.read_at == None,
					UserAnnouncement.dismissed_at == None,
				)
			)
		)
	q = q.order_by(Announcement.is_pinned.desc(), Announcement.updated_at.desc())
	items, total, page, total_pages = _paginate(q, page, limit)
	out_items: List[Dict[str, Any]] = []
	for a, ua in items:
		item = _to_dict(a)
		item["is_read"] = bool(getattr(ua, "read_at", None) is not None)
		item["is_dismissed"] = bool(getattr(ua, "dismissed_at", None) is not None)
		out_items.append(item)
	return {
		"items": out_items,
		"total": total,
		"page": page,
		"limit": limit,
		"total_pages": total_pages,
	}


def mark_read(db: Session, user_id: int, announcement_id: int) -> bool:
	ua = db.query(UserAnnouncement).filter(
		and_(
			UserAnnouncement.user_id == int(user_id),
			UserAnnouncement.announcement_id == int(announcement_id),
		)
	).first()
	now = datetime.utcnow()
	if ua:
		ua.read_at = now
	else:
		ua = UserAnnouncement(user_id=int(user_id), announcement_id=int(announcement_id), read_at=now, first_seen_at=now)
		db.add(ua)
	db.commit()
	return True


def dismiss(db: Session, user_id: int, announcement_id: int) -> bool:
	ua = db.query(UserAnnouncement).filter(
		and_(
			UserAnnouncement.user_id == int(user_id),
			UserAnnouncement.announcement_id == int(announcement_id),
		)
	).first()
	now = datetime.utcnow()
	if ua:
		ua.dismissed_at = now
	else:
		ua = UserAnnouncement(user_id=int(user_id), announcement_id=int(announcement_id), dismissed_at=now, first_seen_at=now)
		db.add(ua)
	db.commit()
	return True


def _parse_dt(val: Any) -> Optional[datetime]:
	if not val:
		return None
	try:
		if isinstance(val, datetime):
			return val
		raw = str(val).strip()
		if not raw:
			return None
		# استانداردسازی پسوند Z به افست قابل‌قبول برای fromisoformat
		if raw.endswith("Z"):
			raw = f"{raw[:-1]}+00:00"
		# اگر افست زمانی بدون دو نقطه باشد (مثلاً +0000)، آن را اصلاح کن
		match = re.match(r"(.+)([+-]\d{2})(\d{2})$", raw)
		if match and ":" not in match.group(2):
			raw = f"{match.group(1)}{match.group(2)}:{match.group(3)}"
		try:
			return datetime.fromisoformat(raw)
		except ValueError:
			# تلاش برای جایگزینی فاصله با T جهت پشتیبانی از فرمت‌های معمول
			normalized = raw.replace(" ", "T")
			return datetime.fromisoformat(normalized)
	except Exception:
		return None


def _to_dict(a: Announcement) -> Dict[str, Any]:
	return {
		"id": a.id,
		"title": a.title,
		"body": a.body,
		"level": a.level,
		"is_pinned": bool(a.is_pinned),
		"is_active": bool(a.is_active),
		"starts_at": a.starts_at.isoformat() if a.starts_at else None,
		"ends_at": a.ends_at.isoformat() if a.ends_at else None,
		"audience_filters": a.audience_filters or {},
		"created_by": a.created_by,
		"created_at": a.created_at.isoformat(),
		"updated_at": a.updated_at.isoformat(),
	}


