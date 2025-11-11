from __future__ import annotations

from typing import Optional, List
from sqlalchemy import select, and_
from sqlalchemy.orm import Session

from adapters.db.models.notification_config import NotificationTemplate, UserNotificationSetting


class NotificationTemplateRepository:
	def __init__(self, db: Session) -> None:
		self.db = db
		self.model = NotificationTemplate

	def get(self, *, event_key: str, channel: str, locale: str | None) -> Optional[NotificationTemplate]:
		stmt = select(self.model).where(
			and_(
				self.model.event_key == event_key,
				self.model.channel == channel,
				self.model.locale == locale,
				self.model.is_active.is_(True),
			)
		)
		obj = self.db.execute(stmt).scalars().first()
		if obj:
			return obj
		# fallback without locale
		if locale:
			stmt2 = select(self.model).where(
				and_(
					self.model.event_key == event_key,
					self.model.channel == channel,
					self.model.locale.is_(None),
					self.model.is_active.is_(True),
				)
			)
			return self.db.execute(stmt2).scalars().first()
		return None

	def list(self, *, event_key: str | None = None, channel: str | None = None) -> List[NotificationTemplate]:
		stmt = select(self.model)
		if event_key:
			stmt = stmt.where(self.model.event_key == event_key)
		if channel:
			stmt = stmt.where(self.model.channel == channel)
		return list(self.db.execute(stmt).scalars().all())

	def create(self, *, event_key: str, channel: str, locale: str | None, subject: str | None, body: str, is_active: bool) -> NotificationTemplate:
		obj = self.model(event_key=event_key, channel=channel, locale=locale, subject=subject, body=body, is_active=is_active)
		self.db.add(obj)
		self.db.commit()
		self.db.refresh(obj)
		return obj

	def update(self, obj: NotificationTemplate, **fields) -> NotificationTemplate:
		for k, v in fields.items():
			setattr(obj, k, v)
		self.db.add(obj)
		self.db.commit()
		self.db.refresh(obj)
		return obj

	def get_by_id(self, template_id: int) -> Optional[NotificationTemplate]:
		return self.db.get(self.model, template_id)

	def delete(self, obj: NotificationTemplate) -> None:
		self.db.delete(obj)
		self.db.commit()


class UserNotificationSettingRepository:
	def __init__(self, db: Session) -> None:
		self.db = db
		self.model = UserNotificationSetting

	def get(self, *, user_id: int, channel: str, event_key: str | None) -> Optional[UserNotificationSetting]:
		stmt = select(self.model).where(
			and_(self.model.user_id == user_id, self.model.channel == channel, self.model.event_key == event_key)
		)
		return self.db.execute(stmt).scalars().first()

	def upsert(self, *, user_id: int, channel: str, event_key: str | None, enabled: bool) -> UserNotificationSetting:
		obj = self.get(user_id=user_id, channel=channel, event_key=event_key)
		if obj:
			obj.enabled = enabled
			self.db.add(obj)
		else:
			obj = self.model(user_id=user_id, channel=channel, event_key=event_key, enabled=enabled)
			self.db.add(obj)
		self.db.commit()
		self.db.refresh(obj)
		return obj

	def list_for_user(self, *, user_id: int) -> List[UserNotificationSetting]:
		stmt = select(self.model).where(self.model.user_id == user_id)
		return list(self.db.execute(stmt).scalars().all())


