from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy import select, desc
from sqlalchemy.orm import Session

from adapters.db.models.api_key import ApiKey


class ApiKeyRepository:
	def __init__(self, db: Session) -> None:
		self.db = db

	def create_session_key(self, *, user_id: int, key_hash: str, device_id: str | None, user_agent: str | None, ip: str | None, expires_at: datetime | None) -> ApiKey:
		obj = ApiKey(user_id=user_id, key_hash=key_hash, key_type="session", name=None, scopes=None, device_id=device_id, user_agent=user_agent, ip=ip, expires_at=expires_at)
		self.db.add(obj)
		self.db.commit()
		self.db.refresh(obj)
		return obj

	def get_by_hash(self, key_hash: str) -> Optional[ApiKey]:
		stmt = select(ApiKey).where(ApiKey.key_hash == key_hash)
		return self.db.execute(stmt).scalars().first()

	def get_user_sessions(self, user_id: int) -> list[ApiKey]:
		"""دریافت تمام session keys فعال کاربر"""
		stmt = select(ApiKey).where(
			ApiKey.user_id == user_id,
			ApiKey.key_type == "session",
			ApiKey.revoked_at.is_(None)
		).order_by(desc(ApiKey.last_used_at), desc(ApiKey.created_at))
		return list(self.db.execute(stmt).scalars().all())

	def revoke_session(self, session_id: int, user_id: int) -> bool:
		"""حذف یک session"""
		stmt = select(ApiKey).where(
			ApiKey.id == session_id,
			ApiKey.user_id == user_id,
			ApiKey.key_type == "session"
		)
		obj = self.db.execute(stmt).scalars().first()
		if not obj:
			return False
		obj.revoked_at = datetime.utcnow()
		self.db.add(obj)
		self.db.commit()
		return True

	def revoke_other_sessions(self, user_id: int, exclude_key_hash: str) -> int:
		"""حذف تمام session های دیگر (به جز session با key_hash مشخص شده)"""
		stmt = select(ApiKey).where(
			ApiKey.user_id == user_id,
			ApiKey.key_type == "session",
			ApiKey.revoked_at.is_(None),
			ApiKey.key_hash != exclude_key_hash
		)
		sessions = list(self.db.execute(stmt).scalars().all())
		count = 0
		for session in sessions:
			session.revoked_at = datetime.utcnow()
			self.db.add(session)
			count += 1
		if count > 0:
			self.db.commit()
		return count


