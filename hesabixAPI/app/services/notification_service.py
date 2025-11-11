from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Dict, Iterable, Optional

from sqlalchemy.orm import Session

from adapters.db.models.notification import NotificationOutbox, NotificationDeliveryAttempt
from adapters.db.repositories.user_repo import UserRepository
from app.services.providers.telegram_provider import TelegramProvider
from app.services.providers.email_provider import EmailProvider
from app.services.providers.inapp_provider import InAppProvider
from adapters.db.repositories.notification_repo import (
	UserNotificationSettingRepository,
	NotificationTemplateRepository,
)
from adapters.db.models.announcement import Announcement, UserAnnouncement


class NotificationService:
	def __init__(self, db: Session) -> None:
		self.db = db
		self.user_repo = UserRepository(db)
		self.telegram = TelegramProvider()
		self.email = EmailProvider(db)
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

	def send(self, *, user_id: int, event_key: str, context: Dict[str, Any], preferred_channels: Optional[Iterable[str]] = None, locale: Optional[str] = None) -> None:
		"""
		Minimal synchronous sender with basic fallback:
		- Try Telegram if linked and requested
		- Else Email
		- Else InApp
		Also records outbox + attempts.
		"""
		user = self.user_repo.db.get(self.user_repo.model_class, user_id)
		if user is None:
			return

		channels = list(preferred_channels) if preferred_channels else ["telegram", "email", "inapp"]

		# Render templates (fallback به متن ساده)
		def render_for(channel: str) -> tuple[str, str]:
			tpl = self.templates.get(event_key=event_key, channel=channel, locale=locale or None)
			if tpl:
				subj = tpl.subject or (context.get("subject") or "پیام سیستم")
				body = tpl.body
			else:
				subj = context.get("subject", "پیام سیستم")
				body = context.get("message", "")
			return subj, body

		subject_email, body_email = render_for("email")
		_, body_tg = render_for("telegram")
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


