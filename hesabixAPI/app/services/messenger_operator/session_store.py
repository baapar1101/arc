# noqa: D100
from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from adapters.db.models.messenger_operator_session import MessengerOperatorSession

FLOW_CRM_WEB_CHAT = "crm_web_chat"

MODE_IDLE = "idle"
MODE_SELECT_BUSINESS = "select_business"
MODE_READY = "ready"
MODE_BROWSING = "browsing"
MODE_IN_CONVERSATION = "in_conversation"


def get_session(db: Session, user_id: int, platform: str) -> MessengerOperatorSession | None:
	return db.scalars(
		select(MessengerOperatorSession).where(
			MessengerOperatorSession.user_id == int(user_id),
			MessengerOperatorSession.platform == platform,
		)
	).first()


def get_or_create_session(db: Session, user_id: int, platform: str) -> MessengerOperatorSession:
	row = get_session(db, user_id, platform)
	if row is None:
		row = MessengerOperatorSession(
			user_id=int(user_id),
			platform=platform,
			flow_key=FLOW_CRM_WEB_CHAT,
			mode=MODE_IDLE,
			context_json={},
			updated_at=datetime.utcnow(),
		)
		db.add(row)
		db.commit()
		db.refresh(row)
	return row


def touch_session(db: Session, row: MessengerOperatorSession) -> None:
	row.updated_at = datetime.utcnow()
	db.add(row)
	db.commit()


def ctx_get(row: MessengerOperatorSession) -> dict[str, Any]:
	return dict(row.context_json or {})


def ctx_set(db: Session, row: MessengerOperatorSession, data: dict[str, Any]) -> None:
	row.context_json = data
	touch_session(db, row)


def reset_session(db: Session, row: MessengerOperatorSession, *, full: bool = False) -> None:
	row.mode = MODE_IDLE
	row.active_conversation_id = None
	row.context_json = {}
	if full:
		row.business_id = None
	touch_session(db, row)
