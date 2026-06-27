from __future__ import annotations

from fastapi import Depends
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.services.system_settings_service import assert_end_user_support_tickets_allowed


def require_end_user_support_open(db: Session = Depends(get_db)) -> None:
	assert_end_user_support_tickets_allowed(db)


def require_support_access(
	db: Session = Depends(get_db),
	current_user: AuthContext = Depends(get_current_user),
) -> None:
	"""کاربران عادی فقط وقتی تیکتینگ فعال است؛ اپراتورها همیشه."""
	if current_user.can_access_support_operator():
		return
	assert_end_user_support_tickets_allowed(db)
