from __future__ import annotations

from typing import Any, Dict
from datetime import date, datetime, timezone
import logging

from fastapi import APIRouter, Depends, Request, Body, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import select

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response
from adapters.db.repositories.bale_repo import BaleRepository
from adapters.db.repositories.user_repo import UserRepository
from adapters.db.models.user import User
from app.services.providers.bale_provider import BaleProvider
from app.services.system_settings_service import get_effective_notifications_settings

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/integrations/bale", tags=["integrations.bale"])


def _iso_expires_at(exp) -> str:
	if isinstance(exp, date) and not isinstance(exp, datetime):
		expires_at_utc = datetime.combine(exp, datetime.min.time(), tzinfo=timezone.utc)
	elif exp.tzinfo is None:
		expires_at_utc = exp.replace(tzinfo=timezone.utc)
	else:
		expires_at_utc = exp.astimezone(timezone.utc)
	return expires_at_utc.isoformat()


@router.post("/link", summary="ایجاد لینک اتصال بله")
def create_link(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	settings = get_effective_notifications_settings(db)
	if not settings.get("bale_bot_token"):
		raise HTTPException(status_code=400, detail="Bale bot is not configured")

	user_id = ctx.get_user_id()
	repo = BaleRepository(db)
	link = repo.create_link_token(
		user_id=user_id,
		ttl_seconds=600,
		created_ip=(request.client.host if request.client else None),
		user_agent=request.headers.get("User-Agent"),
	)
	bot_username = (settings.get("bale_bot_username") or "").strip().lstrip("@")
	# لینک ble.ir اپ موبایل را باز می‌کند؛ web.bale.ai همیشه نسخه وب را باز می‌کند
	if bot_username:
		deep_link = f"https://ble.ir/{bot_username}?start={link.token}"
	else:
		deep_link = None
	return success_response(
		{
			"deep_link": deep_link,
			"link_token": link.token,
			"expires_at": _iso_expires_at(link.expires_at),
		},
		request,
	)


@router.get("/status", summary="وضعیت اتصال بله")
def link_status(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	user = UserRepository(db).db.get(UserRepository(db).model_class, ctx.get_user_id())
	linked = bool(getattr(user, "bale_chat_id", None))
	data: Dict[str, Any] = {"linked": linked}
	if linked:
		data["chat_id"] = getattr(user, "bale_chat_id", None)
		data["connected_at"] = getattr(user, "bale_connected_at", None)
	return success_response(data, request)


@router.delete("/unlink", summary="قطع اتصال بله")
def unlink(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	repo = UserRepository(db)
	user = repo.db.get(repo.model_class, ctx.get_user_id())
	if user is None:
		raise HTTPException(status_code=404, detail="User not found")
	user.bale_chat_id = None  # type: ignore[attr-defined]
	user.bale_connected_at = None  # type: ignore[attr-defined]
	repo.db.add(user)
	repo.db.commit()
	return success_response({"unlinked": True}, request)


@router.post("/webhook/{secret}", summary="وب‌هوک بله", name="bale_webhook")
def bale_webhook(
	secret: str,
	payload: Dict[str, Any] = Body(...),
	request: Request = None,
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	settings = get_effective_notifications_settings(db)
	if not settings.get("bale_webhook_secret") or secret != settings.get("bale_webhook_secret"):
		raise HTTPException(status_code=403, detail="Forbidden")

	provider = BaleProvider(bot_token=settings.get("bale_bot_token"))
	# بله Update می‌فرستد: message یا edited_message
	message = payload.get("message") or payload.get("edited_message") or {}
	text: str = (message.get("text") or "").strip()
	chat = message.get("chat") or {}
	chat_id = chat.get("id")

	# /start <token> -> لینک کردن کاربر
	if text.startswith("/start "):
		token = text.split(" ", 1)[1].strip()
		b_repo = BaleRepository(db)
		link_obj = b_repo.get_by_token(token)
		if not link_obj or link_obj.used_at is not None or link_obj.expires_at < datetime.utcnow():
			if chat_id:
				provider.send_text(chat_id=int(chat_id), text="⛔ لینک اتصال نامعتبر یا منقضی است. لطفاً از داخل برنامه، لینک جدید بسازید.")
			return {"ok": False}
		u_repo = UserRepository(db)
		user = u_repo.db.get(u_repo.model_class, link_obj.user_id)
		if user is None:
			return {"ok": False}
		user.bale_chat_id = int(chat_id) if chat_id else None  # type: ignore[attr-defined]
		user.bale_connected_at = datetime.utcnow()  # type: ignore[attr-defined]
		u_repo.db.add(user)
		u_repo.db.commit()
		b_repo.mark_used(link_obj)
		if chat_id:
			provider.send_text(chat_id=int(chat_id), text="✅ اتصال بله شما با موفقیت برقرار شد.")
		return {"ok": True}

	# /unlink
	if text.startswith("/unlink"):
		if not chat_id:
			return {"ok": False}
		user = db.execute(select(User).where(User.bale_chat_id == int(chat_id))).scalars().first()
		if not user:
			provider.send_text(chat_id=int(chat_id), text="کاربری با این اتصال یافت نشد.")
			return {"ok": False}
		user.bale_chat_id = None  # type: ignore[attr-defined]
		user.bale_connected_at = None  # type: ignore[attr-defined]
		db.add(user)
		db.commit()
		provider.send_text(chat_id=int(chat_id), text="اتصال بله شما قطع شد.")
		return {"ok": True}

	return {"ok": True}
