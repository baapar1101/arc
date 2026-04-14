from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from adapters.db.models.password_reset import PasswordReset


class PasswordResetRepository:
	def __init__(self, db: Session) -> None:
		self.db = db

	def create(self, *, user_id: int, token_hash: str, expires_at: datetime) -> PasswordReset:
		obj = PasswordReset(user_id=user_id, token_hash=token_hash, expires_at=expires_at)
		self.db.add(obj)
		self.db.commit()
		self.db.refresh(obj)
		return obj

	def get_by_hash(self, token_hash: str) -> Optional[PasswordReset]:
		stmt = select(PasswordReset).where(PasswordReset.token_hash == token_hash)
		return self.db.execute(stmt).scalars().first()

	def mark_used(self, pr: PasswordReset) -> None:
		pr.used_at = datetime.utcnow()
		self.db.add(pr)
		self.db.commit()
