from __future__ import annotations

from sqlalchemy.orm import Session

from app.core.auth_dependency import AuthContext


def user_can_manage_ftp_backup(db: Session, ctx: AuthContext, business_id: int) -> bool:
	"""مالک، سوپرادمین، یا کاربر با settings.manage_ftp."""
	if ctx.is_superadmin():
		return True
	if ctx.is_business_owner(business_id):
		return True
	from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository

	repo = BusinessPermissionRepository(db)
	perm_obj = repo.get_by_user_and_business(ctx.get_user_id(), business_id)
	if not perm_obj or not perm_obj.business_permissions:
		return False
	perms = AuthContext._normalize_permissions_value(perm_obj.business_permissions)
	section = perms.get("settings") or {}
	return bool(section.get("manage_ftp"))
