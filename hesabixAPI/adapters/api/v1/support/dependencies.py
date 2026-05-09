from __future__ import annotations

from fastapi import Depends
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.services.system_settings_service import assert_end_user_support_tickets_allowed


def require_end_user_support_open(db: Session = Depends(get_db)) -> None:
	assert_end_user_support_tickets_allowed(db)
