from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Any, Dict, Iterable, Optional, List

from sqlalchemy.orm import Session
from jinja2.sandbox import SandboxedEnvironment
from jinja2 import StrictUndefined, BaseLoader, TemplateSyntaxError, UndefinedError

from adapters.db.models.notification import NotificationOutbox, NotificationDeliveryAttempt
from adapters.db.repositories.user_repo import UserRepository
from app.services.providers.telegram_provider import TelegramProvider
from app.services.providers.email_provider import EmailProvider
from app.services.providers.inapp_provider import InAppProvider
from app.services.providers.sms_provider import SmsProvider
from adapters.db.repositories.notification_repo import (
	UserNotificationSettingRepository,
	NotificationTemplateRepository,
)
from adapters.db.models.announcement import Announcement, UserAnnouncement
from app.services.system_settings_service import get_effective_notifications_settings
from app.utils.phone_utils import normalize_phone_number

logger = logging.getLogger(__name__)


class NotificationService:
	def __init__(self, db: Session) -> None:
		self.db = db
		self.user_repo = UserRepository(db)
		notify_cfg = get_effective_notifications_settings(db)
		self.telegram = TelegramProvider(
			bot_token=notify_cfg.get("telegram_bot_token"),
			proxy_config=notify_cfg.get("telegram_proxy"),
		)
		self.email = EmailProvider(db)
		self.sms = SmsProvider(
			provider_name=notify_cfg.get("sms_provider_name"),
			api_key=notify_cfg.get("sms_api_key"),
			sender=notify_cfg.get("sms_sender"),
			username=notify_cfg.get("sms_provider_username"),
			password=notify_cfg.get("sms_provider_password"),
			is_flash=notify_cfg.get("sms_is_flash", False),
		)
		self.inapp = InAppProvider(db)
		self.user_settings = UserNotificationSettingRepository(db)
		self.templates = NotificationTemplateRepository(db)

	def _create_outbox(self, *, user_id: int, channel: str, event_key: str, payload: Dict[str, Any], locale: Optional[str]) -> NotificationOutbox:
		obj = NotificationOutbox(
			user_id=user_id,
			channel=channel,
			event_key=event_key,
			payload=payload,
			locale=locale,
			status="pending",
			retry_count=0,
			next_attempt_at=None,
		)
		self.db.add(obj)
		self.db.commit()
		self.db.refresh(obj)
		return obj

	def _log_attempt(self, *, outbox_id: int, channel: str, success: bool, error_message: Optional[str]) -> None:
		attempt = NotificationDeliveryAttempt(
			outbox_id=outbox_id,
			channel=channel,
			success=success,
			error_message=error_message,
		)
		self.db.add(attempt)
		self.db.commit()

	def _render_template(self, template_text: str, context: Dict[str, Any]) -> str:
		"""
		رندر کردن قالب Jinja2 با جایگزینی پارامترها
		
		Args:
			template_text: متن قالب (مثلاً "کد ورود شما {{ code }} است")
			context: پارامترهای context برای جایگزینی
		
		Returns:
			متن رندر شده با پارامترهای جایگزین شده
		"""
		if not template_text:
			return ""
		
		try:
			env = SandboxedEnvironment(
				loader=BaseLoader(),
				autoescape=True,
				undefined=StrictUndefined,
				enable_async=False
			)
			template = env.from_string(template_text)
			return template.render(**context)
		except (TemplateSyntaxError, UndefinedError) as e:
			logger.warning(f"خطا در رندر قالب: {e}. متن قالب بدون رندر استفاده می‌شود.")
			# در صورت خطا، متن خام برمی‌گردانیم
			return template_text
		except Exception as e:
			logger.error(f"خطای غیرمنتظره در رندر قالب: {e}", exc_info=True)
			# در صورت خطا، متن خام برمی‌گردانیم
			return template_text

	def send(self, *, user_id: int, event_key: str, context: Dict[str, Any], preferred_channels: Optional[Iterable[str]] = None, locale: Optional[str] = None, broadcast_mode: bool = False) -> bool:
		"""
		Minimal synchronous sender with basic fallback:
		- Try Telegram if linked and requested
		- Else Email
		- Else InApp
		Also records outbox + attempts.
		
		Args:
			user_id: شناسه کاربر
			event_key: کلید رویداد (مثلاً "auth.password_reset")
			context: پارامترهای context برای جایگزینی در قالب (مثلاً {"code": "123456"})
			preferred_channels: لیست کانال‌های ترجیحی برای ارسال
			locale: زبان مورد نظر (اختیاری)
		broadcast_mode: اگر True باشد، به همه کانال‌ها ارسال می‌شود (نه فقط اولین موفق)
		
		Returns:
			True اگر ناتیفیکیشن با موفقیت ارسال شد، False در غیر این صورت
		"""
		user = self.user_repo.db.get(self.user_repo.model_class, user_id)
		if user is None:
			return False

		channels = list(preferred_channels) if preferred_channels else ["telegram", "sms", "email", "inapp"]

		# Render templates با جایگزینی پارامترها (fallback به متن ساده)
		def render_for(channel: str) -> tuple[str, str]:
			tpl = self.templates.get(event_key=event_key, channel=channel, locale=locale or None)
		if tpl:
			# استفاده از قالب با رندر پارامترها
			subj_raw = tpl.subject or (context.get("subject") or "پیام سیستم")
			body_raw = tpl.body or context.get("message", "")
			# رندر کردن subject و body با پارامترهای context
			subj = self._render_template(subj_raw, context)
			body = self._render_template(body_raw, context)
			# اگر بعد از رندر body خالی شد، از context استفاده می‌کنیم
			if not body or not body.strip():
				body = context.get("message", "")
			else:
				# اگر قالب پیدا نشد، از context استفاده می‌کنیم
				subj_raw = context.get("subject", "پیام سیستم")
				body_raw = context.get("message", "")
				
				# Fallback برای auth.otp_login: اگر قالب پیدا نشد و code در context وجود دارد
				if event_key == "auth.otp_login":
					code = context.get("code", "")
					expiry_minutes = context.get("expiry_minutes", 5)
					if code:
						# اگر subject خالی است یا پیش‌فرض است، subject مناسب برای OTP تنظیم می‌کنیم
						if not subj_raw or subj_raw == "پیام سیستم":
							subj_raw = "کد ورود به حساب کاربری"
						# اگر body خالی است، body مناسب برای OTP تنظیم می‌کنیم
						if not body_raw:
							body_raw = f"کد ورود یک بار مصرف شما: {code}\nاین کد تا {expiry_minutes} دقیقه اعتبار دارد."
				
				# حتی اگر قالب نباشد، می‌توانیم پارامترها را جایگزین کنیم
				subj = self._render_template(subj_raw, context)
				body = self._render_template(body_raw, context)
			return subj, body

		subject_email, body_email = render_for("email")
		_, body_tg = render_for("telegram")
		_, body_sms = render_for("sms")
		subject_inapp, body_inapp = render_for("inapp")

		sent = False
		error: Optional[str] = None

		def is_channel_enabled(channel: str) -> bool:
			# Global per-user setting; default True if not set
			row = self.user_settings.get(user_id=user_id, channel=channel, event_key=None)
			return True if row is None else row.enabled

		for channel in channels:
			# احترام به تنظیمات کاربر
			if not is_channel_enabled(channel):
				continue
			outbox = self._create_outbox(user_id=user_id, channel=channel, event_key=event_key, payload=context, locale=locale)
			if channel == "telegram":
				# بررسی پیکربندی تلگرام
				if not self.telegram.is_configured():
					outbox.status = "failed"
					outbox.error_message = "telegram_not_configured"
					self._log_attempt(outbox_id=outbox.id, channel=channel, success=False, error_message="ربات تلگرام پیکربندی نشده است")
					self.db.add(outbox)
					self.db.commit()
					continue
				
				chat_id = getattr(user, "telegram_chat_id", None)
				if not chat_id:
					# No chat connected
					outbox.status = "failed"
					outbox.error_message = "no_telegram_chat_id"
					self._log_attempt(outbox_id=outbox.id, channel=channel, success=False, error_message="کاربر به ربات تلگرام متصل نیست")
					self.db.add(outbox)
					self.db.commit()
					continue
				
				# بررسی اینکه body_tg خالی نباشد - اگر خالی بود، از context استفاده می‌کنیم
				if not body_tg or not body_tg.strip():
					# Fallback به context.get("message")
					body_tg = context.get("message", "")
					if not body_tg or not body_tg.strip():
						outbox.status = "failed"
						outbox.error_message = "empty_telegram_body"
						self._log_attempt(outbox_id=outbox.id, channel=channel, success=False, error_message="متن پیام تلگرام خالی است")
						self.db.add(outbox)
						self.db.commit()
						continue
				
				ok = self.telegram.send_text(chat_id=int(chat_id), text=body_tg)
				self._log_attempt(outbox_id=outbox.id, channel=channel, success=ok, error_message=None if ok else "telegram_send_failed")
				if ok:
					outbox.status = "sent"
					self.db.add(outbox)
					self.db.commit()
					sent = True
					if not broadcast_mode:
						break
				else:
					outbox.status = "failed"
					outbox.retry_count = outbox.retry_count + 1
					outbox.next_attempt_at = datetime.utcnow() + timedelta(minutes=5)
					self.db.add(outbox)
					self.db.commit()
			elif channel == "email":
				# بررسی اینکه body_email خالی نباشد
				if not body_email or not body_email.strip():
					outbox.status = "failed"
					outbox.error_message = "empty_email_body"
					self._log_attempt(outbox_id=outbox.id, channel=channel, success=False, error_message="متن ایمیل خالی است")
					self.db.add(outbox)
					self.db.commit()
					continue
				
				ok = self.email.send(user_id=user_id, subject=subject_email, body_text=body_email)
				self._log_attempt(outbox_id=outbox.id, channel=channel, success=ok, error_message=None if ok else "email_send_failed")
				if ok:
					outbox.status = "sent"
					self.db.add(outbox)
					self.db.commit()
					sent = True
					break
				else:
					outbox.status = "failed"
					outbox.retry_count = outbox.retry_count + 1
					outbox.next_attempt_at = datetime.utcnow() + timedelta(minutes=10)
					self.db.add(outbox)
					self.db.commit()
			elif channel == "sms":
				# بررسی پیکربندی SMS Provider
				if not self.sms.is_configured():
					outbox.status = "failed"
					outbox.error_message = "sms_provider_not_configured"
					self._log_attempt(outbox_id=outbox.id, channel=channel, success=False, error_message="SMS Provider پیکربندی نشده است")
					self.db.add(outbox)
					self.db.commit()
					continue
				
				mobile = getattr(user, "mobile", None)
				if not mobile:
					outbox.status = "failed"
					outbox.error_message = "no_mobile_number"
					self._log_attempt(outbox_id=outbox.id, channel=channel, success=False, error_message="کاربر شماره موبایل ثبت نکرده است")
					self.db.add(outbox)
					self.db.commit()
					continue
				
				# نرمال‌سازی شماره موبایل
				try:
					normalized_mobile = normalize_phone_number(mobile)
				except ValueError as e:
					# شماره موبایل نامعتبر
					error_msg = f"فرمت شماره موبایل نامعتبر: {str(e)}"
					outbox.status = "failed"
					outbox.error_message = "invalid_mobile_number"
					self._log_attempt(outbox_id=outbox.id, channel=channel, success=False, error_message=error_msg)
					self.db.add(outbox)
					self.db.commit()
					continue
				
				# ارسال SMS با مدیریت خطا
				error_msg = None
				ok = False
				try:
					ok, error_msg = self.sms.send_text_with_error(to_phone=normalized_mobile, text=body_sms or context.get("message", ""))
					if not ok and error_msg is None:
						error_msg = "sms_send_failed"
				except Exception as e:
					error_msg = f"خطای غیرمنتظره در ارسال SMS: {str(e)}"
					logger.error(f"خطا در ارسال SMS به {normalized_mobile}: {e}", exc_info=True)
				
				self._log_attempt(outbox_id=outbox.id, channel=channel, success=ok, error_message=error_msg)
				if ok:
					outbox.status = "sent"
					self.db.add(outbox)
					self.db.commit()
					sent = True
					break
				else:
					outbox.status = "failed"
					outbox.error_message = error_msg or "sms_send_failed"
					outbox.retry_count = outbox.retry_count + 1
					outbox.next_attempt_at = datetime.utcnow() + timedelta(minutes=10)
					self.db.add(outbox)
					self.db.commit()
			elif channel == "inapp":
				ok = self.inapp.notify(user_id=user_id, title=subject_inapp, body=body_inapp, level="info")
				self._log_attempt(outbox_id=outbox.id, channel=channel, success=ok, error_message=None if ok else "inapp_failed")
				outbox.status = "sent" if ok else "failed"
				self.db.add(outbox)
				self.db.commit()
				# Persist as an announcement for visibility in UI even if realtime WS is not connected
				# اما برای اعلان‌های پشتیبانی باید audience_filters را به درستی تنظیم کنیم
				try:
					# اگر event_key مربوط به پشتیبانی است، audience_filters را تنظیم می‌کنیم
					audience_filters = None
					if event_key.startswith("support."):
						if event_key == "support.operator_reply":
							# برای پاسخ اپراتور: فقط کاربر صاحب تیکت می‌تواند ببیند
							audience_filters = {
								"allowed_user_ids": [user_id]
							}
						elif event_key == "support.ticket_assigned":
							# برای تخصیص تیکت: فقط اپراتور تخصیص‌یافته می‌تواند ببیند
							# (این اعلان به اپراتور ارسال می‌شود)
							audience_filters = {
								"allowed_user_ids": [user_id]  # user_id در اینجا همان operator_id است
							}
						elif event_key == "support.ticket_status_changed":
							# برای تغییر وضعیت: فقط کاربر صاحب تیکت
							# استخراج user_id از context اگر موجود باشد
							ticket_user_id = context.get("user_id") or user_id
							audience_filters = {
								"allowed_user_ids": [ticket_user_id]
							}
						else:
							# برای سایر اعلان‌های پشتیبانی (ticket_created, user_reply): فقط اپراتورها
							audience_filters = {
								"require_permissions": ["support_operator"]
							}
					
					# محدود کردن محتوای حساس برای اعلان‌های پشتیبانی
					announcement_body = body_inapp or ""
					if event_key.startswith("support."):
						# محدود کردن طول body برای جلوگیری از نمایش اطلاعات حساس
						max_body_length = 500
						if len(announcement_body) > max_body_length:
							announcement_body = announcement_body[:max_body_length] + "..."
					
					a = Announcement(
						title=subject_inapp or "پیام سیستم",
						body=announcement_body,
						level="info",
						is_pinned=False,
						is_active=True,
						starts_at=None,
						ends_at=None,
						audience_filters=audience_filters,
						created_by=None,
					)
					self.db.add(a)
					self.db.commit()
					self.db.refresh(a)
					link = UserAnnouncement(
						user_id=user_id,
						announcement_id=a.id,
						first_seen_at=None,
						read_at=None,
						dismissed_at=None,
					)
					self.db.add(link)
					self.db.commit()
				except Exception:
					# do not fail notification if persistence fails
					pass
				sent = ok
				break
			else:
				outbox.status = "failed"
				outbox.error_message = "unknown_channel"
				self.db.add(outbox)
				self.db.commit()
		
		return sent

	def notify_support_operators(
		self,
		event_key: str,
		context: Dict[str, Any],
		assigned_operator_id: Optional[int] = None,
		locale: Optional[str] = None
	) -> None:
		"""
		ارسال ناتیفیکیشن به اپراتورهای پشتیبانی
		
		Args:
			event_key: کلید رویداد (مثلاً "support.ticket_created")
			context: داده‌های context برای قالب
			assigned_operator_id: اگر مشخص باشد، فقط به این اپراتور ارسال می‌شود
			locale: زبان مورد نظر (اختیاری)
		"""
		import logging
		logger = logging.getLogger(__name__)
		
		if assigned_operator_id:
			# اعتبارسنجی: بررسی اینکه assigned_operator_id واقعاً یک اپراتور است
			if not self.user_repo.is_support_operator(assigned_operator_id):
				logger.warning(f"assigned_operator_id {assigned_operator_id} یک اپراتور معتبر نیست. ارسال به همه اپراتورها")
				assigned_operator_id = None
		
		if assigned_operator_id:
			# ارسال فقط به اپراتور تخصیص‌یافته
			operator = self.user_repo.get_by_id(assigned_operator_id)
			if operator and operator.is_active:
				try:
					self.send(
						user_id=operator.id,
						event_key=event_key,
						context=context,
						preferred_channels=["inapp", "email", "telegram", "sms"],
						locale=locale
					)
				except Exception as e:
					logger.error(f"خطا در ارسال ناتیفیکیشن به اپراتور {operator.id}: {e}")
			else:
				logger.warning(f"اپراتور {assigned_operator_id} یافت نشد یا غیرفعال است")
		else:
			# ارسال به تمام اپراتورها
			operators = self.user_repo.get_support_operators()
			if not operators:
				logger.warning("هیچ اپراتور پشتیبانی فعالی یافت نشد. اعلان ارسال نخواهد شد.")
				return
			
			logger.info(f"ارسال ناتیفیکیشن {event_key} به {len(operators)} اپراتور")
			for operator in operators:
				try:
					telegram_status = f"chat_id={operator.telegram_chat_id}" if operator.telegram_chat_id else "no_telegram_chat_id"
					logger.info(f"ارسال به اپراتور {operator.id} ({operator.email}): {telegram_status}")
					self.send(
						user_id=operator.id,
						event_key=event_key,
						context=context,
						preferred_channels=["inapp", "email", "telegram", "sms"],
						locale=locale
					)
				except Exception as e:
					# در صورت خطا، ادامه می‌دهیم تا به سایر اپراتورها ارسال شود
					logger.error(f"خطا در ارسال ناتیفیکیشن به اپراتور {operator.id}: {e}", exc_info=True)
					continue


