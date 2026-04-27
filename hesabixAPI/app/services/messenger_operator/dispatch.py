# noqa: D100
from __future__ import annotations

import logging
from typing import Any, Callable, Dict, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from adapters.db.models.user import User
from app.services.messenger_operator.crm_web_chat_flow import CrmWebChatMessengerFlow
from app.services.messenger_operator.session_store import get_session

logger = logging.getLogger(__name__)

FLOW_HANDLERS: Dict[str, Any] = {
	CrmWebChatMessengerFlow.flow_key: CrmWebChatMessengerFlow(),
}


def register_operator_flow(flow_key: str, handler: Any) -> None:
	"""ثبت فلو اپراتور جدید (مثلاً از پلاگین). handler باید متد handle(...) مانند CrmWebChatMessengerFlow داشته باشد."""
	FLOW_HANDLERS[flow_key] = handler


def _resolve_user_for_platform(db: Session, platform: str, chat_id: int) -> Optional[User]:
	if platform == "telegram":
		return db.scalars(select(User).where(User.telegram_chat_id == int(chat_id))).first()
	if platform == "bale":
		return db.scalars(select(User).where(User.bale_chat_id == int(chat_id))).first()
	logger.warning("unknown messenger platform=%s", platform)
	return None


def dispatch_operator_messenger_message(
	db: Session,
	*,
	platform: str,
	message: Dict[str, Any],
	send_text: Callable[[str], Any],
) -> bool:
	"""اگر پیام توسط پل اپراتور مصرف شد True."""
	chat = message.get("chat") or {}
	chat_id = chat.get("id")
	if chat_id is None:
		return False

	text = (message.get("text") or message.get("caption") or "").strip()

	user = _resolve_user_for_platform(db, platform, int(chat_id))
	if user is None:
		return False

	sess_row = get_session(db, int(user.id), platform)
	flow_key = sess_row.flow_key if sess_row else CrmWebChatMessengerFlow.flow_key
	handler = FLOW_HANDLERS.get(flow_key) or FLOW_HANDLERS[CrmWebChatMessengerFlow.flow_key]

	try:
		return bool(
			handler.handle(
				db,
				user,
				platform,
				text,
				send_text,
				raw_message=message,
			)
		)
	except Exception:
		logger.exception("messenger operator dispatch failed platform=%s user_id=%s", platform, user.id)
		try:
			send_text("خطای داخلی پل اپراتور. بعداً تلاش کنید.")
		except Exception:
			pass
		return True
