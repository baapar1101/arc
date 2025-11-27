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

	def send(self, *, user_id: int, event_key: str, context: Dict[str, Any], preferred_channels: Optional[Iterable[str]] = None, locale: Optional[str] = None) -> None:
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
		"""
		user = self.user_repo.db.get(self.user_repo.model_class, user_id)
		if user is None:
			return

		channels = list(preferred_channels) if preferred_channels else ["telegram", "sms", "email", "inapp"]

		# Render templates با جایگزینی پارامترها (fallback به متن ساده)
		def render_for(channel: str) -> tuple[str, str]:
			tpl = self.templates.get(event_key=event_key, channel=channel, locale=locale or None)
			if tpl:
				# استفاده از قالب با رندر پارامترها
				subj_raw = tpl.subject or (context.get("subject") or "پیام سیستم")
				body_raw = tpl.body
				# رندر کردن subject و body با پارامترهای context
				subj = self._render_template(subj_raw, context)
				body = self._render_template(body_raw, context)
			else:
				# اگر قالب پیدا نشد، از context استفاده می‌کنیم
				subj_raw = context.get("subject", "پیام سیستم")
				body_raw = context.get("message", "")
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
				chat_id = getattr(user, "telegram_chat_id", None)
				if chat_id:
					ok = self.telegram.send_text(chat_id=int(chat_id), text=body_tg)
					self._log_attempt(outbox_id=outbox.id, channel=channel, success=ok, error_message=None if ok else "telegram_send_failed")
					if ok:
						outbox.status = "sent"
						self.db.add(outbox)
						self.db.commit()
						sent = True
						break
					else:
						outbox.status = "failed"
						outbox.retry_count = outbox.retry_count + 1
						outbox.next_attempt_at = datetime.utcnow() + timedelta(minutes=5)
						self.db.add(outbox)
						self.db.commit()
				else:
					# No chat connected
					outbox.status = "failed"
					outbox.error_message = "no_telegram_chat_id"
					self.db.add(outbox)
					self.db.commit()
					continue
			elif channel == "email":
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
				mobile = getattr(user, "mobile", None)
				if mobile:
					ok = self.sms.send_text(to_phone=mobile, text=body_sms or context.get("message", ""))
					self._log_attempt(outbox_id=outbox.id, channel=channel, success=ok, error_message=None if ok else "sms_send_failed")
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
				else:
					outbox.status = "failed"
					outbox.error_message = "no_mobile_number"
					self.db.add(outbox)
					self.db.commit()
			elif channel == "inapp":
				ok = self.inapp.notify(user_id=user_id, title=subject_inapp, body=body_inapp, level="info")
				self._log_attempt(outbox_id=outbox.id, channel=channel, success=ok, error_message=None if ok else "inapp_failed")
				outbox.status = "sent" if ok else "failed"
				self.db.add(outbox)
				self.db.commit()
				# Persist as an announcement for visibility in UI even if realtime WS is not connected
				try:
					a = Announcement(
						title=subject_inapp or "پیام سیستم",
						body=body_inapp or "",
						level="info",
						is_pinned=False,
						is_active=True,
						starts_at=None,
						ends_at=None,
						audience_filters=None,
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
			# ارسال به تمام اپراتورها
			operators = self.user_repo.get_support_operators()
			for operator in operators:
				try:
					self.send(
						user_id=operator.id,
						event_key=event_key,
						context=context,
						preferred_channels=["inapp", "email", "telegram", "sms"],
						locale=locale
					)
				except Exception as e:
					# در صورت خطا، ادامه می‌دهیم تا به سایر اپراتورها ارسال شود
					logger.error(f"خطا در ارسال ناتیفیکیشن به اپراتور {operator.id}: {e}")
					continue


