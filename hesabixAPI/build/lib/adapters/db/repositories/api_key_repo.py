from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy import select
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


