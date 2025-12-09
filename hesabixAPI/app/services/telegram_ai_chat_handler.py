from __future__ import annotations

from typing import Dict, Any
from datetime import datetime
from sqlalchemy.orm import Session
import logging

from app.services.telegram_ai_chat_service import TelegramAIChatService
from app.services.providers.telegram_provider import TelegramProvider
from adapters.db.repositories.user_repo import UserRepository
from adapters.db.repositories.support.ticket_repository import TicketRepository
from adapters.db.repositories.support.message_repository import MessageRepository
from app.core.auth_dependency import AuthContext

logger = logging.getLogger(__name__)


async def handle_telegram_message(
	message: Dict[str, Any],
	db: Session,
	telegram_provider: TelegramProvider
) -> bool:
	"""پردازش پیام متنی از تلگرام"""
	chat = message.get("chat", {})
	chat_id = chat.get("id")
	text: str = message.get("text", "").strip()
	
	logger.info(f"Processing telegram message: chat_id={chat_id}, text={text[:50] if text else 'empty'}")
	
	if not chat_id or not text:
		logger.warning(f"Invalid message: chat_id={chat_id}, text={text[:50] if text else 'empty'}")
		return False
	
	# پیدا کردن کاربر از chat_id
	user = get_user_by_telegram_chat_id(db, chat_id)
	if not user:
		logger.warning(f"User not found for chat_id: {chat_id}")
		# ارسال پیام به کاربر که اتصال برقرار نشده است
		telegram_provider.send_text(
			chat_id=chat_id,
			text="❌ اتصال تلگرام شما برقرار نشده است.\n\nلطفاً از داخل برنامه، لینک اتصال تلگرام را ایجاد کنید و دوباره امتحان کنید."
		)
		return False
	
	# ایجاد service
	try:
		service = TelegramAIChatService(db, user.id, chat_id, telegram_provider)
		user_context = service._create_auth_context()
		logger.info(f"Service created for user_id={user.id}, chat_id={chat_id}")
	except Exception as e:
		logger.error(f"Error creating service: {e}", exc_info=True)
		if chat_id:
			telegram_provider.send_text(
				chat_id=chat_id,
				text="❌ خطا در ایجاد سرویس. لطفاً دوباره امتحان کنید."
			)
		return False
	
	# بررسی دستورات
	if text == "/start":
		# اگر لینک شده، منوی اصلی را نمایش بده
		logger.info(f"Handling /start command for chat_id={chat_id}")
		return service.send_main_menu(user_context)
	elif text == "/menu":
		logger.info(f"Handling /menu command for chat_id={chat_id}")
		return service.send_main_menu(user_context)
	elif text == "/help":
		logger.info(f"Handling /help command for chat_id={chat_id}")
		help_text = """🤖 دستیار هوش مصنوعی Hesabix

دستورات:
/menu - نمایش منوی اصلی
/help - راهنمای استفاده

برای شروع گفت‌وگو با AI، از منوی اصلی استفاده کنید."""
		return telegram_provider.send_text(chat_id=chat_id, text=help_text)
	
	# پردازش پیام متنی به عنوان سوال از AI
	logger.info(f"Processing AI message for chat_id={chat_id}, text={text[:50]}")
	try:
		result = await service.process_message(text, user_context)
		logger.info(f"process_message result for chat_id={chat_id}: {result}")
		return result
	except Exception as e:
		logger.error(f"Error in process_message: {e}", exc_info=True)
		if chat_id:
			telegram_provider.send_text(
				chat_id=chat_id,
				text="❌ خطا در پردازش پیام شما. لطفاً دوباره امتحان کنید."
			)
		return False


async def handle_telegram_callback_query(
	callback_query: Dict[str, Any],
	db: Session,
	telegram_provider: TelegramProvider
) -> bool:
	"""پردازش Callback Query از دکمه‌ها"""
	chat = callback_query.get("message", {}).get("chat", {})
	chat_id = chat.get("id")
	callback_data = callback_query.get("data", "")
	query_id = callback_query.get("id", "")
	
	if not chat_id or not callback_data:
		return False
	
	# پاسخ به callback query (برای حذف loading)
	telegram_provider.answer_callback_query(query_id)
	
	# پیدا کردن کاربر از chat_id
	user = get_user_by_telegram_chat_id(db, chat_id)
	if not user:
		logger.warning(f"User not found for chat_id: {chat_id}")
		return False
	
	# ایجاد service
	service = TelegramAIChatService(db, user.id, chat_id, telegram_provider)
	user_context = service._create_auth_context()
	
	# تجزیه callback_data
	parts = callback_data.split(":")
	
	try:
		if parts[0] == "menu":
			return await handle_menu_callback(service, user_context, parts[1:])
		elif parts[0] == "chat":
			return await handle_chat_callback(service, user_context, parts[1:])
		elif parts[0] == "ticket":
			return await handle_ticket_callback(service, user_context, parts[1:], db)
		elif parts[0] == "admin":
			return await handle_admin_callback(service, user_context, parts[1:], db)
		elif parts[0] == "back":
			return await handle_back_callback(service, user_context, parts[1:])
		else:
			logger.warning(f"Unknown callback_data: {callback_data}")
			return False
	except Exception as e:
		logger.error(f"Error handling callback query: {e}", exc_info=True)
		return telegram_provider.send_text(
			chat_id=chat_id,
			text=f"❌ خطا در پردازش درخواست: {str(e)}"
		)


async def handle_menu_callback(
	service: TelegramAIChatService,
	user_context: AuthContext,
	parts: list[str]
) -> bool:
	"""پردازش callback منو"""
	if not parts:
		return False
	
	menu_type = parts[0]
	
	if menu_type == "main":
		return service.send_main_menu(user_context)
	elif menu_type == "chat":
		return service.send_chat_menu(user_context)
	elif menu_type == "sessions":
		return service.send_sessions_menu(user_context)
	elif menu_type == "tickets":
		# بررسی دسترسی
		if not user_context.can_access_support_operator():
			return service.telegram_provider.send_text(
				chat_id=service.chat_id,
				text="❌ شما دسترسی به این بخش ندارید."
			)
		return await send_tickets_menu(service, user_context)
	elif menu_type == "admin":
		# بررسی دسترسی
		if not user_context.is_superadmin():
			return service.telegram_provider.send_text(
				chat_id=service.chat_id,
				text="❌ شما دسترسی به این بخش ندارید."
			)
		return send_admin_menu(service, user_context)
	
	return False


async def handle_chat_callback(
	service: TelegramAIChatService,
	user_context: AuthContext,
	parts: list[str]
) -> bool:
	"""پردازش callback گفت‌وگو"""
	if not parts:
		return False
	
	action = parts[0]
	
	if action == "business" and len(parts) > 1:
		business_id = int(parts[1])
		return service.handle_business_selection(business_id, user_context)
	elif action == "new":
		return service.send_chat_menu(user_context)
	elif action == "session" and len(parts) > 1:
		session_id = int(parts[1])
		return await handle_session_selection(service, user_context, session_id)
	elif action == "ask":
		return service.telegram_provider.send_text(
			chat_id=service.chat_id,
			text="لطفاً سوال خود را بنویسید:"
		)
	
	return False


async def handle_ticket_callback(
	service: TelegramAIChatService,
	user_context: AuthContext,
	parts: list[str],
	db: Session
) -> bool:
	"""پردازش callback تیکت"""
	# بررسی دسترسی
	if not user_context.can_access_support_operator():
		return service.telegram_provider.send_text(
			chat_id=service.chat_id,
			text="❌ شما دسترسی به این بخش ندارید."
		)
	
	if len(parts) < 2:
		return False
	
	ticket_id = int(parts[1])
	
	if len(parts) == 2:
		# مشاهده تیکت
		return await send_ticket_details(service, user_context, ticket_id, db)
	elif len(parts) == 3:
		action = parts[2]
		if action == "suggest_reply":
			return await handle_suggest_reply(service, user_context, ticket_id, db)
		elif action == "auto_reply":
			return await handle_auto_reply(service, user_context, ticket_id, db)
	
	return False


async def handle_admin_callback(
	service: TelegramAIChatService,
	user_context: AuthContext,
	parts: list[str],
	db: Session
) -> bool:
	"""پردازش callback مدیریت"""
	# بررسی دسترسی
	if not user_context.is_superadmin():
		return service.telegram_provider.send_text(
			chat_id=service.chat_id,
			text="❌ شما دسترسی به این بخش ندارید."
		)
	
	if not parts:
		return False
	
	action = parts[0]
	
	if action == "stats":
		return await send_admin_stats(service, user_context, db)
	
	return False


async def handle_back_callback(
	service: TelegramAIChatService,
	user_context: AuthContext,
	parts: list[str]
) -> bool:
	"""پردازش callback بازگشت"""
	if not parts:
		return False
	
	back_to = parts[0]
	
	if back_to == "main":
		return service.send_main_menu(user_context)
	elif back_to == "chat":
		return service.send_chat_menu(user_context)
	elif back_to == "tickets":
		return await send_tickets_menu(service, user_context)
	elif back_to == "admin":
		return await send_admin_menu(service, user_context)
	
	return False


def get_user_by_telegram_chat_id(db: Session, chat_id: int):
	"""پیدا کردن کاربر از chat_id تلگرام"""
	from sqlalchemy import select
	from adapters.db.models.user import User
	
	user = db.execute(
		select(User).where(User.telegram_chat_id == chat_id)
	).scalars().first()
	
	return user


async def send_tickets_menu(
	service: TelegramAIChatService,
	user_context: AuthContext
) -> bool:
	"""ارسال منوی تیکت‌ها"""
	from adapters.api.v1.schemas import QueryInfo
	
	ticket_repo = TicketRepository(service.db)
	query_info = QueryInfo(skip=0, take=20, filters=None, sort_by="created_at", sort_desc=True)
	tickets, total = ticket_repo.get_operator_tickets(query_info)
	
	if not tickets:
		buttons = [
			[{"text": "🔄 به‌روزرسانی", "callback_data": "menu:tickets"}],
			[{"text": "⬅️ بازگشت", "callback_data": "back:main"}]
		]
		keyboard = service._build_inline_keyboard(buttons)
		return service.telegram_provider.send_text(
			chat_id=service.chat_id,
			text="تیکت باز وجود ندارد.",
			reply_markup=keyboard
		)
	
	buttons: list[list[dict[str, str]]] = []
	
	# دکمه‌های تیکت‌ها (3 در هر ردیف)
	for i in range(0, min(len(tickets), 9), 3):  # حداکثر 9 تیکت
		row: list[dict[str, str]] = []
		for j in range(3):
			if i + j < len(tickets):
				ticket = tickets[i + j]
				priority_emoji = _get_priority_emoji(ticket.priority.name if ticket.priority else "medium")
				row.append({
					"text": f"{priority_emoji} #{ticket.id}",
					"callback_data": f"ticket:{ticket.id}"
				})
		if row:
			buttons.append(row)
	
	buttons.append([{"text": "🔄 به‌روزرسانی", "callback_data": "menu:tickets"}])
	buttons.append([{"text": "⬅️ بازگشت", "callback_data": "back:main"}])
	
	keyboard = service._build_inline_keyboard(buttons)
	
	text = f"تیکت‌های باز ({total}):\n\n"
	for ticket in tickets[:9]:
		priority_emoji = _get_priority_emoji(ticket.priority.name if ticket.priority else "medium")
		text += f"{priority_emoji} #{ticket.id} - {ticket.title}\n"
	
	return service.telegram_provider.send_text(
		chat_id=service.chat_id,
		text=text,
		reply_markup=keyboard
	)


async def send_ticket_details(
	service: TelegramAIChatService,
	user_context: AuthContext,
	ticket_id: int,
	db: Session
) -> bool:
	"""ارسال جزئیات تیکت"""
	ticket_repo = TicketRepository(db)
	ticket = ticket_repo.get_operator_ticket_with_details(ticket_id)
	
	if not ticket:
		return service.telegram_provider.send_text(
			chat_id=service.chat_id,
			text="❌ تیکت یافت نشد."
		)
	
	priority_emoji = _get_priority_emoji(ticket.priority.name if ticket.priority else "medium")
	user_name = f"{ticket.user.first_name or ''} {ticket.user.last_name or ''}".strip() if ticket.user else "نامشخص"
	
	text = f"""تیکت #{ticket.id}:

👤 کاربر: {user_name}
📌 موضوع: {ticket.title}
{priority_emoji} اولویت: {ticket.priority.name if ticket.priority else 'نامشخص'}
📅 تاریخ: {ticket.created_at.strftime('%Y/%m/%d %H:%M') if ticket.created_at else 'نامشخص'}

📝 توضیحات:
{ticket.description[:500]}{'...' if len(ticket.description) > 500 else ''}"""
	
	buttons = [
		[{"text": "🤖 پیشنهاد پاسخ AI", "callback_data": f"ticket:{ticket_id}:suggest_reply"}],
		[{"text": "✉️ پاسخ خودکار AI", "callback_data": f"ticket:{ticket_id}:auto_reply"}],
		[{"text": "⬅️ بازگشت", "callback_data": "back:tickets"}]
	]
	keyboard = service._build_inline_keyboard(buttons)
	
	return service.telegram_provider.send_text(
		chat_id=service.chat_id,
		text=text,
		reply_markup=keyboard
	)


async def handle_suggest_reply(
	service: TelegramAIChatService,
	user_context: AuthContext,
	ticket_id: int,
	db: Session
) -> bool:
	"""پیشنهاد پاسخ AI برای تیکت"""
	from adapters.db.repositories.support.ticket_repository import TicketRepository
	from adapters.db.repositories.support.message_repository import MessageRepository
	from app.services.ai.ai_service import AIService
	from app.core.responses import ApiError
	
	# ارسال پیام "در حال پردازش..."
	service.telegram_provider.send_text(
		chat_id=service.chat_id,
		text="⏳ در حال دریافت پیشنهاد پاسخ AI..."
	)
	
	try:
		ticket_repo = TicketRepository(db)
		ticket = ticket_repo.get_operator_ticket_with_details(ticket_id)
		
		if not ticket:
			return service.telegram_provider.send_text(
				chat_id=service.chat_id,
				text="❌ تیکت یافت نشد."
			)
		
		# دریافت تاریخچه تیکت
		ticket_messages = ticket.messages if ticket.messages else []
		
		# ساخت context برای AI
		context_messages = []
		for msg in ticket_messages:
			sender_type_str = msg.sender_type.value if hasattr(msg.sender_type, 'value') else str(msg.sender_type)
			context_messages.append({
				"role": "user" if sender_type_str == "user" else "assistant",
				"content": msg.content
			})
		
		# ایجاد AI Service
		# توجه: برای اپراتورها نیازی به business_id نیست چون دسترسی سیستمی دارند
		ai_service = AIService(db, user_context)
		
		# ساخت prompt برای AI
		system_prompt = f"""شما یک دستیار هوشمند برای اپراتورهای پشتیبانی هستید.
تیکت مربوط به کاربر {ticket.user.first_name or ''} {ticket.user.last_name or ''} است.
موضوع تیکت: {ticket.title}
دسته‌بندی: {ticket.category.name if ticket.category else 'نامشخص'}
اولویت: {ticket.priority.name if ticket.priority else 'نامشخص'}

لطفاً یک پاسخ حرفه‌ای و مفید برای این تیکت پیشنهاد دهید."""
		
		# ارسال به AI
		ai_messages = [
			{"role": "system", "content": system_prompt},
			*context_messages,
			{"role": "user", "content": f"لطفاً برای این تیکت پاسخ مناسبی پیشنهاد دهید:\n\n{ticket.description}"}
		]
		
		response = await ai_service.chat_completion(ai_messages, use_function_calling=True)
		
		# بررسی سهمیه و شارژ
		usage = response.get("usage", {})
		input_tokens = usage.get("input_tokens", 0)
		output_tokens = usage.get("output_tokens", 0)
		
		charge_result = ai_service.check_quota_and_charge(input_tokens, output_tokens)
		
		# ثبت لاگ استفاده
		ai_service.log_usage(
			provider=ai_service.config.provider if ai_service.config else "openai",
			model=ai_service.config.model_name if ai_service.config else "gpt-4",
			input_tokens=input_tokens,
			output_tokens=output_tokens,
			cost=charge_result.get("cost", 0),
			payment_method=charge_result.get("payment_method", "free"),
			wallet_transaction_id=charge_result.get("wallet_transaction_id"),
			document_id=charge_result.get("document_id"),
			context={"ticket_id": ticket_id, "type": "suggest_reply"}
		)
		
		suggested_reply = response["message"]["content"]
		
		if not suggested_reply:
			return service.telegram_provider.send_text(
				chat_id=service.chat_id,
				text="❌ پیشنهادی دریافت نشد."
			)
		
		# محدود کردن طول
		if len(suggested_reply) > 4000:
			suggested_reply = suggested_reply[:4000] + "\n\n... (متن کامل در برنامه قابل مشاهده است)"
		
		buttons = [
			[{"text": "⬅️ بازگشت", "callback_data": f"ticket:{ticket_id}"}]
		]
		keyboard = service._build_inline_keyboard(buttons)
		
		return service.telegram_provider.send_text(
			chat_id=service.chat_id,
			text=f"✅ پیشنهاد پاسخ:\n\n{suggested_reply}",
			reply_markup=keyboard
		)
	except Exception as e:
		logger.error(f"Error suggesting reply: {e}", exc_info=True)
		return service.telegram_provider.send_text(
			chat_id=service.chat_id,
			text=f"❌ خطا در دریافت پیشنهاد: {str(e)}"
		)


async def handle_auto_reply(
	service: TelegramAIChatService,
	user_context: AuthContext,
	ticket_id: int,
	db: Session
) -> bool:
	"""پاسخ خودکار AI به تیکت"""
	from adapters.db.repositories.support.ticket_repository import TicketRepository
	from adapters.db.repositories.support.message_repository import MessageRepository
	from app.services.ai.ai_service import AIService
	from app.services.notification_service import NotificationService
	
	# ارسال پیام "در حال پردازش..."
	service.telegram_provider.send_text(
		chat_id=service.chat_id,
		text="⏳ در حال ارسال پاسخ خودکار..."
	)
	
	try:
		# دریافت پیشنهاد پاسخ (از handle_suggest_reply استفاده می‌کنیم)
		# اما این بار مستقیماً ارسال می‌کنیم
		ticket_repo = TicketRepository(db)
		ticket = ticket_repo.get_operator_ticket_with_details(ticket_id)
		
		if not ticket:
			return service.telegram_provider.send_text(
				chat_id=service.chat_id,
				text="❌ تیکت یافت نشد."
			)
		
		# دریافت تاریخچه تیکت
		ticket_messages = ticket.messages if ticket.messages else []
		
		# ساخت context برای AI
		context_messages = []
		for msg in ticket_messages:
			sender_type_str = msg.sender_type.value if hasattr(msg.sender_type, 'value') else str(msg.sender_type)
			context_messages.append({
				"role": "user" if sender_type_str == "user" else "assistant",
				"content": msg.content
			})
		
		# ایجاد AI Service
		# توجه: برای اپراتورها نیازی به business_id نیست چون دسترسی سیستمی دارند
		ai_service = AIService(db, user_context)
		
		# ساخت prompt برای AI
		system_prompt = f"""شما یک دستیار هوشمند برای اپراتورهای پشتیبانی هستید.
تیکت مربوط به کاربر {ticket.user.first_name or ''} {ticket.user.last_name or ''} است.
موضوع تیکت: {ticket.title}
دسته‌بندی: {ticket.category.name if ticket.category else 'نامشخص'}
اولویت: {ticket.priority.name if ticket.priority else 'نامشخص'}

لطفاً یک پاسخ حرفه‌ای و مفید برای این تیکت پیشنهاد دهید."""
		
		# ارسال به AI
		ai_messages = [
			{"role": "system", "content": system_prompt},
			*context_messages,
			{"role": "user", "content": f"لطفاً برای این تیکت پاسخ مناسبی پیشنهاد دهید:\n\n{ticket.description}"}
		]
		
		response = await ai_service.chat_completion(ai_messages, use_function_calling=True)
		
		# بررسی سهمیه و شارژ
		usage = response.get("usage", {})
		input_tokens = usage.get("input_tokens", 0)
		output_tokens = usage.get("output_tokens", 0)
		
		charge_result = ai_service.check_quota_and_charge(input_tokens, output_tokens)
		
		# ثبت لاگ استفاده
		ai_service.log_usage(
			provider=ai_service.config.provider if ai_service.config else "openai",
			model=ai_service.config.model_name if ai_service.config else "gpt-4",
			input_tokens=input_tokens,
			output_tokens=output_tokens,
			cost=charge_result.get("cost", 0),
			payment_method=charge_result.get("payment_method", "free"),
			wallet_transaction_id=charge_result.get("wallet_transaction_id"),
			document_id=charge_result.get("document_id"),
			context={"ticket_id": ticket_id, "type": "auto_reply"}
		)
		
		suggested_reply = response["message"]["content"]
		
		# ارسال پیام
		message_repo = MessageRepository(db)
		message = message_repo.create_message(
			ticket_id=ticket_id,
			sender_id=user_context.get_user_id(),
			sender_type="operator",
			content=suggested_reply,
			is_internal=False
		)
		
		# تخصیص تیکت به اپراتور (اگر هنوز تخصیص نشده)
		if ticket and not ticket.assigned_operator_id:
			ticket_repo.assign_ticket(ticket_id, user_context.get_user_id())
		
		db.commit()
		
		# ارسال ناتیفیکیشن به کاربر
		if ticket and ticket.user_id:
			try:
				notification_service = NotificationService(db)
				operator_name = f"{user_context.user.first_name or ''} {user_context.user.last_name or ''}".strip() or "اپراتور پشتیبانی"
				message_preview = suggested_reply[:200] + ("..." if len(suggested_reply) > 200 else "")
				
				context = {
					"subject": f"پاسخ جدید به تیکت #{ticket_id}",
					"message": f"اپراتور {operator_name} به تیکت شما پاسخ داد:\n\n{message_preview}",
					"ticket_id": ticket_id,
					"ticket_title": ticket.title if hasattr(ticket, 'title') else "تیکت",
					"operator_name": operator_name,
					"message_preview": message_preview
				}
				
			notification_service.send(
				user_id=ticket.user_id,
				event_key="support.operator_reply",
				context=context,
				preferred_channels=["inapp", "email", "telegram", "sms"],
				broadcast_mode=False
			)
			except Exception as e:
				logger.error(f"خطا در ارسال ناتیفیکیشن برای پاسخ AI به تیکت {ticket_id}: {e}")
		
		return service.telegram_provider.send_text(
			chat_id=service.chat_id,
			text="✅ پاسخ AI به تیکت ارسال شد.\nکاربر مطلع شد."
		)
	except Exception as e:
		logger.error(f"Error auto replying: {e}", exc_info=True)
		return service.telegram_provider.send_text(
			chat_id=service.chat_id,
			text=f"❌ خطا در ارسال پاسخ: {str(e)}"
		)


async def send_admin_menu(
	service: TelegramAIChatService,
	user_context: AuthContext
) -> bool:
	"""ارسال منوی مدیریت"""
	buttons = [
		[{"text": "📊 آمار سیستم", "callback_data": "admin:stats"}],
		[{"text": "⬅️ بازگشت", "callback_data": "back:main"}]
	]
	keyboard = service._build_inline_keyboard(buttons)
	
	return service.telegram_provider.send_text(
		chat_id=service.chat_id,
		text="مدیریت سیستم:",
		reply_markup=keyboard
	)


async def send_admin_stats(
	service: TelegramAIChatService,
	user_context: AuthContext,
	db: Session
) -> bool:
	"""ارسال آمار سیستم"""
	from sqlalchemy import func, select
	from adapters.db.models.user import User
	from adapters.db.models.support.ticket import Ticket
	from adapters.db.models.ai_usage_log import AIUsageLog
	
	# شمارش کاربران فعال
	active_users = db.execute(
		select(func.count(User.id)).where(User.is_active == True)  # noqa: E712
	).scalar() or 0
	
	# شمارش تیکت‌های باز
	open_tickets = db.execute(
		select(func.count(Ticket.id)).where(Ticket.status_id.is_(None))
	).scalar() or 0
	
	# استفاده AI (آخرین 30 روز)
	from datetime import timedelta
	thirty_days_ago = datetime.utcnow() - timedelta(days=30)
	ai_usage = db.execute(
		select(func.sum(AIUsageLog.input_tokens + AIUsageLog.output_tokens))
		.where(AIUsageLog.created_at >= thirty_days_ago)
	).scalar() or 0
	
	text = f"""📊 آمار سیستم:

👥 کاربران فعال: {active_users}
🎫 تیکت‌های باز: {open_tickets}
🤖 استفاده AI (30 روز): {ai_usage:,} توکن"""
	
	buttons = [
		[{"text": "⬅️ بازگشت", "callback_data": "back:admin"}]
	]
	keyboard = service._build_inline_keyboard(buttons)
	
	return service.telegram_provider.send_text(
		chat_id=service.chat_id,
		text=text,
		reply_markup=keyboard
	)


async def handle_session_selection(
	service: TelegramAIChatService,
	user_context: AuthContext,
	session_id: int
) -> bool:
	"""مدیریت انتخاب جلسه"""
	ai_session = service.ai_chat_repo.get_by_id(session_id)
	if not ai_session:
		return service.telegram_provider.send_text(
			chat_id=service.chat_id,
			text="❌ جلسه یافت نشد."
		)
	
	# به‌روزرسانی جلسه تلگرام
	service.session_repo.create_or_update_session(
		user_id=service.user_id,
		chat_id=service.chat_id,
		session_id=session_id,
		business_id=ai_session.business_id
	)
	
	# دریافت آخرین پیام‌ها
	messages = service.ai_message_repo.get_session_messages(session_id, limit=5)
	
	text = f"✅ جلسه '{ai_session.title}' انتخاب شد.\n\n"
	if messages:
		text += "آخرین پیام‌ها:\n"
		for msg in messages[-3:]:
			role = "شما" if msg.role == "user" else "AI"
			content = msg.content[:100] + "..." if len(msg.content) > 100 else msg.content
			text += f"\n{role}: {content}\n"
	
	buttons = [
		[{"text": "💬 ادامه گفت‌وگو", "callback_data": "chat:ask"}],
		[{"text": "⬅️ بازگشت", "callback_data": "back:chat"}]
	]
	keyboard = service._build_inline_keyboard(buttons)
	
	return service.telegram_provider.send_text(
		chat_id=service.chat_id,
		text=text,
		reply_markup=keyboard
	)


def _get_priority_emoji(priority: str) -> str:
	"""تبدیل اولویت به emoji"""
	priority_map = {
		"high": "🔴",
		"medium": "🟡",
		"low": "🟢"
	}
	return priority_map.get(priority.lower(), "⚪")

