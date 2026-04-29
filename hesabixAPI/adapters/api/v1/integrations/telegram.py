from __future__ import annotations

from typing import Any, Dict
from datetime import date, datetime, timezone
import logging

from fastapi import APIRouter, Depends, Request, Body, HTTPException
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response
from adapters.db.repositories.telegram_repo import TelegramRepository
from adapters.db.repositories.user_repo import UserRepository
from app.services.providers.telegram_provider import TelegramProvider
from app.services.system_settings_service import get_effective_notifications_settings

logger = logging.getLogger(__name__)
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
	deep_link_crm = f"https://t.me/{bot_username}?start=crm" if bot_username else None
	# اطمینان از اینکه expires_at با Z (UTC) برگردانده می‌شود
	# پشتیبانی از date و datetime (برخی دیتابیس‌ها date برمی‌گردانند)
	exp = link.expires_at
	if isinstance(exp, date) and not isinstance(exp, datetime):
		expires_at_utc = datetime.combine(exp, datetime.min.time(), tzinfo=timezone.utc)
	elif exp.tzinfo is None:
		expires_at_utc = exp.replace(tzinfo=timezone.utc)
	else:
		expires_at_utc = exp.astimezone(timezone.utc)
	expires_at_iso = expires_at_utc.isoformat()
	return success_response(
		{
			"deep_link": deep_link,
			"deep_link_crm": deep_link_crm,
			"link_token": link.token,
			"expires_at": expires_at_iso,
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


@router.post("/webhook/{secret}", summary="وبهوک تلگرام", name="telegram_webhook")
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

	if text.startswith("/start"):
		_start_parts = text.split(maxsplit=1)
		if len(_start_parts) == 2 and _start_parts[1].strip().lower() == "crm":
			from sqlalchemy import select
			from adapters.db.models.user import User
			from app.services.messenger_operator.dispatch import dispatch_operator_messenger_message

			if chat_id:
				u_crm = db.execute(select(User).where(User.telegram_chat_id == int(chat_id))).scalars().first()
				if u_crm:

					def _crm_send(msg: str, inline_keyboard: Any = None) -> Any:
						rm = {"inline_keyboard": inline_keyboard} if inline_keyboard else None
						return provider.send_text(int(chat_id), msg, parse_mode=None, reply_markup=rm)

					dispatch_operator_messenger_message(
						db,
						platform="telegram",
						message={"chat": {"id": chat_id}, "text": "/crmchat"},
						send=_crm_send,
					)
				else:
					provider.send_text(
						chat_id=int(chat_id),
						text="❌ ابتدا تلگرام را از داخل برنامه متصل کنید.",
					)
			return {"ok": True}
		if len(_start_parts) == 2:
			token = _start_parts[1].strip()
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
				provider.send_text(chat_id=int(chat_id), text="✅ اتصال تلگرام شما با موفقیت برقرار شد.\n\n👋 خوش آمدید! من دستیار هوش مصنوعی شما هستم.\n\nبرای شروع از منوی اصلی استفاده کنید:")
				# ارسال منوی اصلی
				from app.services.telegram_ai_chat_service import TelegramAIChatService
				from app.core.auth_dependency import AuthContext
				service = TelegramAIChatService(db, user.id, int(chat_id), provider)
				# برای تلگرام، api_key_id را 0 می‌گذاریم (نشان می‌دهد از طریق تلگرام است)
				user_context = AuthContext(db=db, user=user, api_key_id=0)
				service.send_main_menu(user_context)
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

	# پردازش پیام‌های AI Chat
	if "message" in payload:
		message = payload["message"]
		chat = message.get("chat", {})
		chat_id_inner = chat.get("id")
		# پل اپراتور (چت وب CRM و فلوهای بعدی)
		if chat_id_inner:
			from app.services.messenger_operator.dispatch import dispatch_operator_messenger_message

			def _operator_send(msg: str, inline_keyboard: Any = None) -> Any:
				rm = {"inline_keyboard": inline_keyboard} if inline_keyboard else None
				return provider.send_text(int(chat_id_inner), msg, parse_mode=None, reply_markup=rm)

			if dispatch_operator_messenger_message(
				db,
				platform="telegram",
				message=message,
				send=_operator_send,
			):
				pass
			else:
				# فقط پیام‌های متنی را به AI بفرست (نه دستورات /)
				text_ai = message.get("text", "").strip()
				if text_ai and not text_ai.startswith("/"):
					from app.services.telegram_ai_chat_handler import handle_telegram_message
					import asyncio

					chat_id = chat_id_inner
					try:
						result = asyncio.run(handle_telegram_message(message, db, provider))
						if not result and chat_id:
							logger.warning(f"handle_telegram_message returned False for chat_id: {chat_id}")
					except RuntimeError:
						try:
							loop = asyncio.get_event_loop()
							if loop.is_running():
								import concurrent.futures

								with concurrent.futures.ThreadPoolExecutor() as executor:
									future = executor.submit(asyncio.run, handle_telegram_message(message, db, provider))
									result = future.result(timeout=60)
									if not result and chat_id:
										logger.warning(f"handle_telegram_message returned False for chat_id: {chat_id}")
							else:
								result = loop.run_until_complete(handle_telegram_message(message, db, provider))
								if not result and chat_id:
									logger.warning(f"handle_telegram_message returned False for chat_id: {chat_id}")
						except Exception as e:
							logger.error(f"Error handling telegram message: {e}", exc_info=True)
							if chat_id:
								try:
									provider.send_text(
										chat_id=chat_id,
										text="❌ خطا در پردازش پیام شما. لطفاً دوباره امتحان کنید.",
									)
								except Exception as send_error:
									logger.error(f"Error sending error message to user: {send_error}", exc_info=True)
					except Exception as e:
						logger.error(f"Error handling telegram message: {e}", exc_info=True)
						if chat_id:
							try:
								provider.send_text(
									chat_id=chat_id,
									text="❌ خطا در پردازش پیام شما. لطفاً دوباره امتحان کنید.",
								)
							except Exception as send_error:
								logger.error(f"Error sending error message to user: {send_error}", exc_info=True)
	
	# پردازش Callback Query (فشار دادن دکمه)
	if "callback_query" in payload:
		callback_query = payload["callback_query"]
		from app.services.telegram_ai_chat_handler import handle_telegram_callback_query
		import asyncio
		try:
			# استفاده از asyncio.run برای ایجاد event loop جدید
			asyncio.run(handle_telegram_callback_query(callback_query, db, provider))
		except RuntimeError:
			# اگر event loop از قبل وجود دارد، از get_event_loop استفاده می‌کنیم
			try:
				loop = asyncio.get_event_loop()
				if loop.is_running():
					# اگر loop در حال اجرا است، از create_task استفاده می‌کنیم
					import concurrent.futures
					with concurrent.futures.ThreadPoolExecutor() as executor:
						future = executor.submit(asyncio.run, handle_telegram_callback_query(callback_query, db, provider))
						future.result(timeout=60)
				else:
					loop.run_until_complete(handle_telegram_callback_query(callback_query, db, provider))
			except Exception as e:
				logger.error(f"Error handling callback query: {e}", exc_info=True)
		except Exception as e:
			logger.error(f"Error handling callback query: {e}", exc_info=True)
	
	return {"ok": True}


