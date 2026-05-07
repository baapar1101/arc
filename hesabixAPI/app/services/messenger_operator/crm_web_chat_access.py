# noqa: D100
from __future__ import annotations

from typing import List, Tuple

from sqlalchemy import select
from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.business_permission import BusinessPermission
from adapters.db.models.user import User
from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
from app.core.auth_dependency import AuthContext
from app.core.crm_web_chat_permissions import check_crm_web_chat_capability


def is_superadmin_user(user: User) -> bool:
	ap = user.app_permissions or {}
	if not isinstance(ap, dict):
		return False
	return bool(ap.get("superadmin"))


def user_can_reply_crm_web_chat(db: Session, user: User, business_id: int) -> bool:
	"""فقط مالک کسب‌وکار یا عضو با مجوز پاسخ‌گویی چت وب CRM (سوپرادمین از این قاعده مستثنی نیست)."""
	b = db.get(Business, int(business_id))
	if not b or b.deleted_at is not None:
		return False
	if int(b.owner_id) == int(user.id):
		return True
	repo = BusinessPermissionRepository(db)
	po = repo.get_by_user_and_business(int(user.id), int(business_id))
	if not po:
		return False
	perms = AuthContext._normalize_permissions_value(po.business_permissions or {})
	if not perms.get("join"):
		return False
	return check_crm_web_chat_capability(perms, "reply")


def user_has_crm_web_chat_messenger_access(db: Session, user: User) -> bool:
	"""آیا کاربر حداقل یک کسب‌وکار دارد که بتواند از پیام‌رسان چت وب CRM را به‌عنوان عامل استفاده کند؟"""
	return bool(iter_reply_allowed_businesses(db, user))


def iter_reply_allowed_businesses(db: Session, user: User) -> List[Tuple[int, str]]:
	"""کسب‌وکارهایی که کاربر می‌تواند در چت وب به‌عنوان عامل پاسخ دهد (مالک یا عضو با مجوز reply)."""
	out: List[Tuple[int, str]] = []
	seen: set[int] = set()

	owned = db.scalars(
		select(Business).where(Business.owner_id == int(user.id), Business.deleted_at.is_(None))
	).all()
	for b in owned:
		if b.id not in seen:
			seen.add(int(b.id))
			out.append((int(b.id), (b.name or "").strip() or f"کسب‌وکار {b.id}"))

	for bp in db.scalars(select(BusinessPermission).where(BusinessPermission.user_id == int(user.id))).all():
		perms = AuthContext._normalize_permissions_value(bp.business_permissions or {})
		if not perms.get("join"):
			continue
		if not check_crm_web_chat_capability(perms, "reply"):
			continue
		b = db.get(Business, int(bp.business_id))
		if not b or b.deleted_at is not None:
			continue
		bid = int(b.id)
		if bid in seen:
			continue
		seen.add(bid)
		out.append((bid, (b.name or "").strip() or f"کسب‌وکار {bid}"))

	return out


def iter_messenger_crm_business_page(
	db: Session,
	user: User,
	*,
	offset: int = 0,
	limit: int = 10,
) -> Tuple[List[Tuple[int, str]], bool]:
	"""
	صفحه‌ای از کسب‌وکارهای قابل انتخاب برای چت وب در پیام‌رسان.
	فقط همان فهرست مجاز (مالک یا عضو با دسترسی CRM chat reply)؛ بدون لیست سراسری.
	"""
	off = max(0, int(offset))
	lim = max(1, min(int(limit), 25))
	all_allowed = iter_reply_allowed_businesses(db, user)
	slice_ = all_allowed[off : off + lim + 1]
	has_more = len(slice_) > lim
	return slice_[:lim], has_more
