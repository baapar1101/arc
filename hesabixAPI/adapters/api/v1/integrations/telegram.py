from __future__ import annotations

from typing import Any, Dict
from datetime import datetime

from fastapi import APIRouter, Depends, Request, Body, HTTPException
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response
from adapters.db.repositories.telegram_repo import TelegramRepository
from adapters.db.repositories.user_repo import UserRepository
from app.services.providers.telegram_provider import TelegramProvider
from app.services.system_settings_service import get_effective_notifications_settings

router = APIRouter(prefix="/integrations/telegram", tags=["integrations.telegram"])


@router.post("/link", summary="ایجاد لینک اتصال تلگرام")
def create_link(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	settings = get_effective_notifications_settings(db)
	if not settings.get("telegram_bot_token"):
		raise HTTPException(status_code=400, detail="Telegram bot is not configured")

	user_id = ctx.get_user_id()
	repo = TelegramRepository(db)
	link = repo.create_link_token(
		user_id=user_id,
		ttl_seconds=600,
		created_ip=(request.client.host if request.client else None),
		user_agent=request.headers.get("User-Agent"),
	)
	bot_username = settings.get("telegram_bot_username") or ""
	deep_link = f"https://t.me/{bot_username}?start={link.token}" if bot_username else None
	return success_response(
		{
			"deep_link": deep_link,
			"link_token": link.token,
			"expires_at": link.expires_at.isoformat(),
		},
		request,
	)


@router.get("/status", summary="وضعیت اتصال تلگرام")
def link_status(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	user = UserRepository(db).db.get(UserRepository(db).model_class, ctx.get_user_id())
	linked = bool(getattr(user, "telegram_chat_id", None))
	data: Dict[str, Any] = {
		"linked": linked,
	}
	if linked:
		data["chat_id"] = getattr(user, "telegram_chat_id", None)
		data["connected_at"] = getattr(user, "telegram_connected_at", None)
	return success_response(data, request)


@router.delete("/unlink", summary="قطع اتصال تلگرام")
def unlink(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	repo = UserRepository(db)
	user = repo.db.get(repo.model_class, ctx.get_user_id())
	if user is None:
		raise HTTPException(status_code=404, detail="User not found")
	user.telegram_chat_id = None  # type: ignore[attr-defined]
	user.telegram_connected_at = None  # type: ignore[attr-defined]
	repo.db.add(user)
	repo.db.commit()
	return success_response({"unlinked": True}, request)


@router.post("/webhook/{secret}", summary="وبهوک تلگرام")
def telegram_webhook(
	secret: str,
	payload: Dict[str, Any] = Body(...),
	request: Request = None,
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	settings = get_effective_notifications_settings(db)
	if not settings.get("telegram_webhook_secret") or secret != settings.get("telegram_webhook_secret"):
		raise HTTPException(status_code=403, detail="Forbidden")
	if settings.get("telegram_secret_header"):
		header_val = request.headers.get("X-Telegram-Bot-Api-Secret-Token") if request else None
		if header_val != settings.get("telegram_secret_header"):
			raise HTTPException(status_code=403, detail="Forbidden")
	
	# تنظیم proxy_config برای TelegramProvider تا بتواند پیام‌ها را از طریق پروکسی ارسال کند
	proxy_cfg = settings.get("telegram_proxy") or {}
	provider = TelegramProvider(
		bot_token=settings.get("telegram_bot_token"),
		proxy_config=proxy_cfg if proxy_cfg.get("enabled") else None
	)

	message = payload.get("message") or {}
	text: str = message.get("text") or ""
	chat = message.get("chat") or {}
	chat_id = chat.get("id")

	if text.startswith("/start "):
		token = text.split(" ", 1)[1].strip()
		t_repo = TelegramRepository(db)
		t_obj = t_repo.get_by_token(token)
		if not t_obj or t_obj.used_at is not None or t_obj.expires_at < datetime.utcnow():
			if chat_id:
				provider.send_text(chat_id=int(chat_id), text="⛔️ لینک اتصال نامعتبر یا منقضی است. لطفاً از داخل برنامه، لینک جدید بسازید.")
			return {"ok": False}
		# Link user to chat
		u_repo = UserRepository(db)
		user = u_repo.db.get(u_repo.model_class, t_obj.user_id)
		if user is None:
			return {"ok": False}
		user.telegram_chat_id = int(chat_id) if chat_id else None  # type: ignore[attr-defined]
		user.telegram_connected_at = datetime.utcnow()  # type: ignore[attr-defined]
		u_repo.db.add(user)
		u_repo.db.commit()
		t_repo.mark_used(t_obj)
		if chat_id:
			provider.send_text(chat_id=int(chat_id), text="✅ اتصال تلگرام شما با موفقیت برقرار شد.\nاز این پس پیام‌های مهم برایتان ارسال می‌شود.")
		return {"ok": True}

	# Optional: unlink command
	if text.strip().startswith("/unlink"):
		if not chat_id:
			return {"ok": False}
		u_repo = UserRepository(db)
		# find user by chat_id
		from sqlalchemy import select
		from adapters.db.models.user import User
		user = db.execute(select(User).where(User.telegram_chat_id == int(chat_id))).scalars().first()
		if not user:
			provider.send_text(chat_id=int(chat_id), text="کاربری با این اتصال یافت نشد.")
			return {"ok": False}
		user.telegram_chat_id = None  # type: ignore[attr-defined]
		user.telegram_connected_at = None  # type: ignore[attr-defined]
		db.add(user)
		db.commit()
		provider.send_text(chat_id=int(chat_id), text="اتصال تلگرام شما قطع شد.")
		return {"ok": True}

	# Optional commands like /unlink could be handled later
	return {"ok": True}


