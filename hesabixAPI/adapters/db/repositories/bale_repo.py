from __future__ import annotations

from datetime import datetime, timedelta
from typing import Optional
import secrets

from sqlalchemy import select
from sqlalchemy.orm import Session

from adapters.db.models.bale import BaleLinkToken


class BaleRepository:
	def __init__(self, db: Session) -> None:
		self.db = db

	def create_link_token(
		self,
		*,
		user_id: int,
		ttl_seconds: int,
		created_ip: str | None,
		user_agent: str | None,
	) -> BaleLinkToken:
		token = secrets.token_urlsafe(32)
		expires_at = datetime.utcnow() + timedelta(seconds=ttl_seconds)
		obj = BaleLinkToken(
			user_id=user_id,
			token=token,
			expires_at=expires_at,
			created_ip=created_ip,
			user_agent=user_agent,
		)
		self.db.add(obj)
		self.db.commit()
		self.db.refresh(obj)
		return obj

	def get_by_token(self, token: str) -> Optional[BaleLinkToken]:
		stmt = select(BaleLinkToken).where(BaleLinkToken.token == token)
		return self.db.execute(stmt).scalars().first()

	def mark_used(self, obj: BaleLinkToken) -> None:
		obj.used_at = datetime.utcnow()
		self.db.add(obj)
		self.db.commit()
		self.db.refresh(obj)
