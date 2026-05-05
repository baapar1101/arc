from __future__ import annotations

from typing import Optional, List, Tuple
from sqlalchemy import select, and_
from sqlalchemy.orm import Session

from adapters.db.models.notification_config import (
	NotificationTemplate,
	UserNotificationSetting,
	UserInappAlertPreference,
)


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

	def list(self, *, event_key: str | None = None, channel: str | None = None, is_active: bool | None = None) -> List[NotificationTemplate]:
		stmt = select(self.model)
		if event_key:
			stmt = stmt.where(self.model.event_key == event_key)
		if channel:
			stmt = stmt.where(self.model.channel == channel)
		if is_active is not None:
			stmt = stmt.where(self.model.is_active.is_(is_active))
		return list(self.db.execute(stmt).scalars().all())

	def exists(self, *, event_key: str, channel: str, locale: str | None, exclude_id: int | None = None) -> bool:
		"""بررسی وجود قالب با همان event_key, channel, locale"""
		stmt = select(self.model).where(
			and_(
				self.model.event_key == event_key,
				self.model.channel == channel,
				(self.model.locale == locale) if locale is not None else (self.model.locale.is_(None)),
			)
		)
		if exclude_id is not None:
			stmt = stmt.where(self.model.id != exclude_id)
		obj = self.db.execute(stmt).scalars().first()
		return obj is not None

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


class UserInappAlertPreferenceRepository:
	def __init__(self, db: Session) -> None:
		self.db = db
		self.model = UserInappAlertPreference

	def get_for_user(self, *, user_id: int) -> Optional[UserInappAlertPreference]:
		stmt = select(self.model).where(self.model.user_id == user_id)
		return self.db.execute(stmt).scalars().first()

	def get_or_defaults(self, *, user_id: int) -> Tuple[str, bool, str]:
		row = self.get_for_user(user_id=user_id)
		if row is None:
			return ("normal", True, "default")
		return (row.alert_mode, row.sound_enabled, row.sound_asset_id)

	def upsert(
		self,
		*,
		user_id: int,
		alert_mode: str,
		sound_enabled: bool,
		sound_asset_id: str,
	) -> UserInappAlertPreference:
		obj = self.get_for_user(user_id=user_id)
		if obj is None:
			obj = self.model(
				user_id=user_id,
				alert_mode=alert_mode,
				sound_enabled=sound_enabled,
				sound_asset_id=sound_asset_id,
			)
			self.db.add(obj)
		else:
			obj.alert_mode = alert_mode
			obj.sound_enabled = sound_enabled
			obj.sound_asset_id = sound_asset_id
			self.db.add(obj)
		self.db.commit()
		self.db.refresh(obj)
		return obj


