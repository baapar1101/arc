from __future__ import annotations

from typing import Dict, Any, List, Optional
from datetime import datetime
from sqlalchemy.orm import Session
import logging

from app.core.auth_dependency import AuthContext
from app.services.ai.ai_service import AIService
from app.services.providers.telegram_provider import TelegramProvider
from adapters.db.repositories.telegram_repo import TelegramAISessionRepository
from adapters.db.repositories.ai_chat_repository import AIChatSessionRepository, AIChatMessageRepository
from adapters.db.repositories.business_repo import BusinessRepository
from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
from app.services.business_service import get_user_businesses

logger = logging.getLogger(__name__)


class TelegramAIChatService:
	"""سرویس مدیریت چت AI از طریق تلگرام"""
	
	def __init__(
		self,
		db: Session,
		user_id: int,
		chat_id: int,
		telegram_provider: TelegramProvider
	):
		self.db = db
		self.user_id = user_id
		self.chat_id = chat_id
		self.telegram_provider = telegram_provider
		self.session_repo = TelegramAISessionRepository(db)
		self.ai_chat_repo = AIChatSessionRepository(db)
		self.ai_message_repo = AIChatMessageRepository(db)
		self.business_repo = BusinessRepository(db)
		self.permission_repo = BusinessPermissionRepository(db)
	
	def _create_auth_context(self) -> AuthContext:
		"""ایجاد AuthContext برای کاربر"""
		from adapters.db.repositories.user_repo import UserRepository
		user_repo = UserRepository(self.db)
		user = user_repo.get_by_id(self.user_id)
		if not user:
			raise ValueError(f"User {self.user_id} not found")
		
		from app.core.auth_dependency import AuthContext
		# برای تلگرام، api_key_id را 0 می‌گذاریم (نشان می‌دهد از طریق تلگرام است)
		return AuthContext(db=self.db, user=user, api_key_id=0)
	
	def _build_inline_keyboard(self, buttons: List[List[Dict[str, str]]]) -> Dict[str, Any]:
		"""ساخت Inline Keyboard از لیست دکمه‌ها"""
		return {"inline_keyboard": buttons}
	
	def send_main_menu(self, user_context: AuthContext) -> bool:
		"""ارسال منوی اصلی بر اساس دسترسی کاربر"""
		buttons: List[List[Dict[str, str]]] = []
		
		# دکمه‌های عمومی
		buttons.append([{"text": "💬 گفت‌وگو با AI", "callback_data": "menu:chat"}])
		
		# دکمه تیکت‌ها (فقط برای اپراتورها)
		if user_context.can_access_support_operator():
			buttons.append([{"text": "🎫 تیکت‌های پشتیبانی", "callback_data": "menu:tickets"}])
		
		# دکمه مدیریت (فقط برای SuperAdmin)
		if user_context.is_superadmin():
			buttons.append([{"text": "👥 مدیریت سیستم", "callback_data": "menu:admin"}])
		
		# دکمه‌های عمومی دیگر
		buttons.append([
			{"text": "📊 گزارش‌های سریع", "callback_data": "menu:reports"},
			{"text": "🔍 جستجو", "callback_data": "menu:search"}
		])
		buttons.append([{"text": "📋 جلسات من", "callback_data": "menu:sessions"}])
		buttons.append([{"text": "⚙️ تنظیمات", "callback_data": "menu:settings"}])
		
		keyboard = self._build_inline_keyboard(buttons)
		return self.telegram_provider.send_text(
			chat_id=self.chat_id,
			text="منوی اصلی:",
			reply_markup=keyboard
		)
	
	def send_chat_menu(self, user_context: AuthContext) -> bool:
		"""ارسال منوی انتخاب کسب‌وکار برای گفت‌وگو"""
		# دریافت کسب‌وکارهای کاربر
		query_info = {"skip": 0, "take": 100}
		businesses_result = get_user_businesses(self.db, self.user_id, query_info)
		businesses = businesses_result.get("items", [])
		
		buttons: List[List[Dict[str, str]]] = []
		
		# دکمه‌های کسب‌وکارها (حداکثر 2 در هر ردیف)
		for i in range(0, len(businesses), 2):
			row: List[Dict[str, str]] = []
			for j in range(2):
				if i + j < len(businesses):
					business = businesses[i + j]
					business_name = business.get("name", f"کسب‌وکار {business.get('id')}")
					# محدود کردن طول نام برای دکمه
					if len(business_name) > 20:
						business_name = business_name[:17] + "..."
					row.append({
						"text": f"🏢 {business_name}",
						"callback_data": f"chat:business:{business.get('id')}"
					})
			if row:
				buttons.append(row)
		
		buttons.append([{"text": "➕ گفت‌وگوی جدید", "callback_data": "chat:new"}])
		buttons.append([{"text": "⬅️ بازگشت", "callback_data": "back:main"}])
		
		keyboard = self._build_inline_keyboard(buttons)
		return self.telegram_provider.send_text(
			chat_id=self.chat_id,
			text="لطفاً کسب‌وکار خود را انتخاب کنید:",
			reply_markup=keyboard
		)
	
	def send_sessions_menu(self, user_context: AuthContext) -> bool:
		"""ارسال منوی جلسات"""
		sessions = self.session_repo.get_user_sessions(self.user_id, self.chat_id, limit=10)
		
		if not sessions:
			buttons = [
				[{"text": "➕ گفت‌وگوی جدید", "callback_data": "chat:new"}],
				[{"text": "⬅️ بازگشت", "callback_data": "back:main"}]
			]
			keyboard = self._build_inline_keyboard(buttons)
			return self.telegram_provider.send_text(
				chat_id=self.chat_id,
				text="جلسه‌ای وجود ندارد. برای شروع گفت‌وگوی جدید، دکمه زیر را بزنید:",
				reply_markup=keyboard
			)
		
		buttons: List[List[Dict[str, str]]] = []
		
		# دکمه‌های جلسات (3 در هر ردیف)
		for i in range(0, len(sessions), 3):
			row: List[Dict[str, str]] = []
			for j in range(3):
				if i + j < len(sessions):
					session = sessions[i + j]
					session_id = session.session_id or 0
					emoji = "1️⃣" if j == 0 else ("2️⃣" if j == 1 else "3️⃣")
					row.append({
						"text": f"{emoji}",
						"callback_data": f"chat:session:{session_id}"
					})
			if row:
				buttons.append(row)
		
		buttons.append([{"text": "➕ گفت‌وگوی جدید", "callback_data": "chat:new"}])
		buttons.append([{"text": "⬅️ بازگشت", "callback_data": "back:main"}])
		
		keyboard = self._build_inline_keyboard(buttons)
		
		# ساخت متن لیست جلسات
		sessions_text = "جلسات فعال شما:\n\n"
		for idx, session in enumerate(sessions[:10], 1):
			title = "گفت‌وگوی جدید"
			if session.session_id:
				ai_session = self.ai_chat_repo.get_by_id(session.session_id)
				if ai_session:
					title = ai_session.title
			sessions_text += f"{idx}. {title}\n"
		
		return self.telegram_provider.send_text(
			chat_id=self.chat_id,
			text=sessions_text,
			reply_markup=keyboard
		)
	
	def handle_business_selection(self, business_id: int, user_context: AuthContext) -> bool:
		"""مدیریت انتخاب کسب‌وکار"""
		# بررسی دسترسی به کسب‌وکار
		business = self.business_repo.get_by_id(business_id)
		if not business:
			return self.telegram_provider.send_text(
				chat_id=self.chat_id,
				text="❌ کسب‌وکار یافت نشد."
			)
		
		# بررسی دسترسی کاربر
		if business.owner_id != self.user_id:
			permission = self.permission_repo.get_by_user_and_business(self.user_id, business_id)
			if not permission:
				return self.telegram_provider.send_text(
					chat_id=self.chat_id,
					text="❌ شما به این کسب‌وکار دسترسی ندارید."
				)
		
		# دریافت یا ایجاد جلسه AI
		ai_sessions = self.ai_chat_repo.get_user_sessions(
			user_id=self.user_id,
			business_id=business_id,
			limit=1
		)
		
		if ai_sessions:
			ai_session = ai_sessions[0]
		else:
			# ایجاد جلسه جدید
			from adapters.db.models.ai_chat_session import AIChatSession
			ai_session = AIChatSession(
				user_id=self.user_id,
				business_id=business_id,
				title="گفت‌وگوی جدید"
			)
			self.db.add(ai_session)
			self.db.commit()
			self.db.refresh(ai_session)
		
		# ایجاد یا به‌روزرسانی جلسه تلگرام
		telegram_session = self.session_repo.create_or_update_session(
			user_id=self.user_id,
			chat_id=self.chat_id,
			session_id=ai_session.id,
			business_id=business_id
		)
		
		# ارسال پیام تایید
		buttons = [
			[{"text": "💬 سوال بپرس", "callback_data": "chat:ask"}],
			[{"text": "📊 گزارش مالی", "callback_data": "chat:report"}],
			[{"text": "🔍 جستجوی محصول", "callback_data": "chat:search_product"}],
			[{"text": "📦 لیست فاکتورها", "callback_data": "chat:invoices"}],
			[{"text": "⬅️ بازگشت", "callback_data": "back:chat"}]
		]
		keyboard = self._build_inline_keyboard(buttons)
		
		return self.telegram_provider.send_text(
			chat_id=self.chat_id,
			text=f"✅ گفت‌وگو با کسب‌وکار {business.name} شروع شد.\n\nچه کمکی می‌تونم بکنم؟",
			reply_markup=keyboard
		)
	
	async def process_message(self, text: str, user_context: AuthContext) -> bool:
		"""پردازش پیام متنی و ارسال به AI"""
		# دریافت جلسه فعال
		active_session = self.session_repo.get_active_session(self.user_id, self.chat_id)
		if not active_session or not active_session.session_id:
			return self.telegram_provider.send_text(
				chat_id=self.chat_id,
				text="❌ ابتدا یک کسب‌وکار را انتخاب کنید.",
				reply_markup=self._build_inline_keyboard([
					[{"text": "🏢 انتخاب کسب‌وکار", "callback_data": "menu:chat"}]
				])
			)
		
		# بررسی اجباری business_id (چون کیف پول‌ها business-specific هستند)
		if not active_session.business_id:
			logger.warning(f"Session without business_id for user {self.user_id}, chat {self.chat_id}")
			return self.telegram_provider.send_text(
				chat_id=self.chat_id,
				text="❌ کسب‌وکار انتخاب شده نامعتبر است. لطفاً دوباره کسب‌وکار را انتخاب کنید.",
				reply_markup=self._build_inline_keyboard([
					[{"text": "🏢 انتخاب کسب‌وکار", "callback_data": "menu:chat"}]
				])
			)
		
		# چک اعتبار قبل از ارسال (بدون try-except گسترده)
		ai_service = AIService(self.db, user_context, active_session.business_id)
		availability = ai_service.check_availability(estimated_tokens=len(text) * 2)
		
		if not availability["can_use"]:
			return self._send_availability_error(availability)
		
		# ارسال پیام "در حال پردازش..."
		self.telegram_provider.send_text(
			chat_id=self.chat_id,
			text="⏳ در حال پردازش..."
		)
		
		try:
			# ارسال به AI
			ai_service = AIService(self.db, user_context, active_session.business_id)
			
			# دریافت پیام‌های قبلی
			previous_messages = self.ai_message_repo.get_session_messages(
				active_session.session_id,
				limit=50
			)
			
			# ساخت messages برای AI
			messages = []
			for msg in previous_messages:
				messages.append({
					"role": msg.role if isinstance(msg.role, str) else getattr(msg.role, "value", msg.role),
					"content": msg.content
				})
			
			# اضافه کردن پیام جدید
			messages.append({
				"role": "user",
				"content": text
			})
			
			# ذخیره پیام کاربر
			from adapters.db.models.ai_chat_message import AIChatMessage, MessageRole
			user_message = AIChatMessage(
				session_id=active_session.session_id,
				role=MessageRole.USER.value,
				content=text,
				tokens_used=0
			)
			self.db.add(user_message)
			self.db.commit()
			self.db.refresh(user_message)
			
			# ارسال به AI (async)
			response = await ai_service.chat_completion(
				messages=messages,
				use_function_calling=True,
				session_business_id=active_session.business_id
			)
			
			# بررسی سهمیه و شارژ
			usage = response.get("usage", {})
			input_tokens = usage.get("input_tokens", 0)
			output_tokens = usage.get("output_tokens", 0)
			
			charge_result = ai_service.check_quota_and_charge(input_tokens, output_tokens)
			
			# ذخیره پاسخ AI
			assistant_message = AIChatMessage(
				session_id=active_session.session_id,
				role=MessageRole.ASSISTANT.value,
				content=response["message"]["content"],
				tokens_used=input_tokens + output_tokens
			)
			self.db.add(assistant_message)
			
			# ثبت لاگ استفاده
			ai_service.log_usage(
				provider=ai_service.config.provider if ai_service.config else "openai",
				model=ai_service.config.model_name if ai_service.config else "gpt-4",
				input_tokens=input_tokens,
				output_tokens=output_tokens,
				cost=charge_result.get("cost", 0),
				payment_method=charge_result.get("payment_method", "free"),
				wallet_transaction_id=charge_result.get("wallet_transaction_id"),
				document_id=charge_result.get("document_id")
			)
			
			# به‌روزرسانی زمان جلسه
			ai_session = self.ai_chat_repo.get_by_id(active_session.session_id)
			if ai_session:
				ai_session.updated_at = datetime.utcnow()
				# اگر عنوان پیش‌فرض است و این اولین پیام است، عنوان هوشمند بساز
				if ai_session.title == "گفت‌وگوی جدید" or ai_session.title == "جلسه چت جدید":
					generated_title = await ai_service.generate_chat_title(text)
					if generated_title:
						ai_session.title = generated_title[:80]
			
			self.db.commit()
			
			# ارسال پاسخ
			response_text = response["message"]["content"]
			# محدود کردن طول پیام (حداکثر 4096 کاراکتر)
			if len(response_text) > 4000:
				response_text = response_text[:4000] + "\n\n... (متن کامل در برنامه قابل مشاهده است)"
			
			buttons = [
				[{"text": "💬 سوال دیگر", "callback_data": "chat:ask"}],
				[{"text": "⬅️ بازگشت", "callback_data": "back:chat"}]
			]
			keyboard = self._build_inline_keyboard(buttons)
			
			return self.telegram_provider.send_text(
				chat_id=self.chat_id,
				text=response_text,
				reply_markup=keyboard
			)
			
		except Exception as e:
			logger.error(f"Error processing AI message: {e}", exc_info=True)
			
			# بررسی نوع خطا و نمایش پیام مناسب
			error_message = "❌ خطا در پردازش پیام"
			from app.core.responses import ApiError
			
			if isinstance(e, ApiError):
				error_code = e.error_code
				
				if error_code == "NO_ACTIVE_SUBSCRIPTION":
					error_message = """❌ اشتراک فعالی ندارید

برای استفاده از هوش مصنوعی، ابتدا یک پلن را از داخل برنامه انتخاب کنید.

💡 پلن‌های موجود:
• رایگان: ۵۰۰۰ توکن
• پایه: ۵۰٬۰۰۰ توکن ماهانه
• حرفه‌ای: نامحدود"""
				
				elif error_code == "QUOTA_EXCEEDED":
					extra_data = getattr(e, 'extra_data', {})
					tokens_used = extra_data.get('tokens_used', 0)
					tokens_limit = extra_data.get('tokens_limit', 0)
					error_message = f"""⚠️ سهمیه شما تمام شده است

استفاده شده: {tokens_used:,}
سقف: {tokens_limit:,}

💡 برای ادامه:
• ارتقا به پلن بالاتر از داخل برنامه
• منتظر تمدید ماهانه بمانید"""
				
				elif error_code == "INSUFFICIENT_FUNDS":
					extra_data = getattr(e, 'extra_data', {})
					wallet = extra_data.get('wallet', {})
					balance = wallet.get('balance', 0)
					estimated_cost = wallet.get('estimated_cost', 0)
					error_message = f"""💰 موجودی کیف پول ناکافی

موجودی فعلی: {balance:,.0f} ریال
هزینه تخمینی: {estimated_cost:,.0f} ریال

لطفاً از داخل برنامه، کیف پول خود را شارژ کنید."""
				
				else:
					error_message = f"❌ خطا: {e.message}"
			else:
				error_message = f"❌ خطا در پردازش پیام: {str(e)}"
			
			return self.telegram_provider.send_text(
				chat_id=self.chat_id,
				text=error_message
			)
	
	def _send_availability_error(self, availability: Dict[str, Any]) -> bool:
		"""ارسال پیام خطای عدم امکان استفاده از AI"""
		reason = availability.get("reason")
		details = availability.get("details", {})
		message = details.get("message", "خطای نامشخص")
		suggestions = details.get("suggestions", [])
		
		if reason == "NO_ACTIVE_SUBSCRIPTION":
			text = """❌ اشتراک فعالی ندارید

برای استفاده از هوش مصنوعی، ابتدا یک پلن را از داخل برنامه انتخاب کنید.

💡 پلن‌های موجود:
• رایگان: ۵۰۰۰ توکن
• پایه: ۵۰٬۰۰۰ توکن ماهانه
• حرفه‌ای: نامحدود"""
		
		elif reason == "QUOTA_EXCEEDED":
			subscription = details.get("subscription", {})
			tokens_used = subscription.get("tokens_used", 0)
			tokens_limit = subscription.get("tokens_limit", 0)
			text = f"""⚠️ سهمیه شما تمام شده است

استفاده شده: {tokens_used:,}
سقف: {tokens_limit:,}

💡 برای ادامه:
• ارتقا به پلن بالاتر از داخل برنامه
• منتظر تمدید ماهانه بمانید"""
		
		elif reason == "INSUFFICIENT_FUNDS":
			wallet = details.get("wallet", {})
			balance = wallet.get("balance", 0)
			estimated_cost = wallet.get("estimated_cost", 0)
			text = f"""💰 موجودی کیف پول ناکافی

موجودی فعلی: {balance:,.0f} ریال
هزینه تخمینی: {estimated_cost:,.0f} ریال

لطفاً از داخل برنامه، کیف پول خود را شارژ کنید."""
		
		else:
			text = f"❌ {message}"
			if suggestions:
				text += "\n\n" + "\n".join(f"• {s}" for s in suggestions)
		
		return self.telegram_provider.send_text(
			chat_id=self.chat_id,
			text=text,
			reply_markup=self._build_inline_keyboard([
				[{"text": "🔙 بازگشت", "callback_data": "back:main"}]
			])
		)

