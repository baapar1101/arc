"""مجوزهای ریزدانه HScript با سازگاری عقب‌رو به reports.*."""

from __future__ import annotations

import logging
from typing import Literal

from fastapi import Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import ApiError

logger = logging.getLogger(__name__)

HScriptAction = Literal["view", "write", "publish", "export", "schedule"]

_LEGACY_FALLBACK: dict[str, tuple[str, str]] = {
	"view": ("reports", "view"),
	"write": ("reports", "view"),
	"publish": ("reports", "view"),
	"export": ("reports", "export"),
	"schedule": ("reports", "view"),
}


def _section_allows(section_perms: dict, action: str) -> bool:
	if not isinstance(section_perms, dict):
		return False
	if not section_perms:
		return action in {"view", "read"}
	return bool(
		section_perms.get(action, False)
		or (action == "write" and (section_perms.get("add") or section_perms.get("edit")))
		or (action == "add" and (section_perms.get("write") or section_perms.get("edit")))
		or (action == "edit" and (section_perms.get("write") or section_perms.get("add")))
	)


def permissions_allow_hscript(permissions: dict | None, action: HScriptAction) -> bool:
	"""چک JSON مجوزها برای اکشن HScript (با fallback)."""
	perms = permissions if isinstance(permissions, dict) else {}
	if "hscript" in perms:
		return _section_allows(perms.get("hscript") or {}, action)
	section, legacy_action = _LEGACY_FALLBACK.get(action, ("reports", "view"))
	return _section_allows(perms.get(section) or {}, legacy_action)


def has_hscript_permission(ctx: AuthContext, action: HScriptAction) -> bool:
	"""برای UI/سرویس وقتی permissions از قبل روی context است."""
	if not ctx.business_id:
		return False
	if ctx.is_superadmin() or ctx.is_business_owner():
		return True
	return permissions_allow_hscript(ctx.business_permissions, action)


def require_hscript_permission_dep(action: HScriptAction, business_id_param: str = "business_id"):
	"""FastAPI dependency برای endpointهای HScript."""

	def _dependency(
		request: Request,
		auth_context: AuthContext = Depends(get_current_user),
		db: Session = Depends(get_db),
	) -> None:
		business_id = None
		try:
			raw = request.path_params.get(business_id_param)
			if raw is not None:
				business_id = int(raw)
		except (ValueError, TypeError, AttributeError):
			business_id = None
		if not business_id:
			raise ApiError("BAD_REQUEST", "business_id parameter not found in path", http_status=400)

		if not auth_context.can_access_business(business_id):
			raise ApiError("FORBIDDEN", f"No access to business {business_id}", http_status=403)

		if auth_context.is_superadmin() or auth_context.is_business_owner(business_id):
			return

		from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository

		repo = BusinessPermissionRepository(db)
		permission_obj = repo.get_by_user_and_business(auth_context.get_user_id(), business_id)
		if not permission_obj or not permission_obj.business_permissions:
			raise ApiError("FORBIDDEN", f"Missing business permission: hscript.{action}", http_status=403)

		permissions = auth_context._normalize_permissions_value(permission_obj.business_permissions)
		if permissions_allow_hscript(permissions, action):
			return
		raise ApiError("FORBIDDEN", f"Missing business permission: hscript.{action}", http_status=403)

	return _dependency
