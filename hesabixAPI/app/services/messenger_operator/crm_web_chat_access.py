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
	b = db.get(Business, int(business_id))
	if not b or b.deleted_at is not None:
		return False
	if is_superadmin_user(user):
		return True
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


def iter_reply_allowed_businesses(db: Session, user: User) -> List[Tuple[int, str]]:
	"""کسب‌وکارهایی که کاربر می‌تواند در چت وب به‌عنوان عامل پاسخ دهد."""
	out: List[Tuple[int, str]] = []
	seen: set[int] = set()

	if is_superadmin_user(user):
		return []

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
