from __future__ import annotations

from datetime import datetime, timedelta
from typing import Optional

from sqlalchemy import select, and_
from sqlalchemy.orm import Session

from adapters.db.models.email_verification import EmailVerificationToken


class EmailVerificationRepository:
	def __init__(self, db: Session) -> None:
		self.db = db

	def create(self, *, user_id: int, email: str, token_hash: str, expires_at: datetime) -> EmailVerificationToken:
		obj = EmailVerificationToken(
			user_id=user_id,
			email=email,
			token_hash=token_hash,
			expires_at=expires_at
		)
		self.db.add(obj)
		self.db.commit()
		self.db.refresh(obj)
		return obj

	def get_by_hash(self, token_hash: str) -> Optional[EmailVerificationToken]:
		stmt = select(EmailVerificationToken).where(
			and_(
				EmailVerificationToken.token_hash == token_hash,
				EmailVerificationToken.used_at.is_(None)
			)
		)
		return self.db.execute(stmt).scalars().first()

	def get_active_by_user(self, user_id: int) -> Optional[EmailVerificationToken]:
		"""دریافت آخرین token فعال کاربر"""
		stmt = select(EmailVerificationToken).where(
			and_(
				EmailVerificationToken.user_id == user_id,
				EmailVerificationToken.used_at.is_(None),
				EmailVerificationToken.expires_at > datetime.utcnow()
			)
		).order_by(EmailVerificationToken.created_at.desc())
		return self.db.execute(stmt).scalars().first()

	def count_recent_by_user(self, user_id: int, hours: int = 1) -> int:
		"""شمارش token های ایجاد شده در N ساعت اخیر"""
		cutoff = datetime.utcnow() - timedelta(hours=hours)
		stmt = select(EmailVerificationToken).where(
			and_(
				EmailVerificationToken.user_id == user_id,
				EmailVerificationToken.created_at >= cutoff
			)
		)
		return len(self.db.execute(stmt).scalars().all())

	def mark_used(self, token: EmailVerificationToken) -> None:
		token.used_at = datetime.utcnow()
		self.db.add(token)
		self.db.commit()

	def delete_expired(self) -> int:
		"""حذف token های منقضی شده"""
		stmt = select(EmailVerificationToken).where(
			EmailVerificationToken.expires_at < datetime.utcnow()
		)
		expired = self.db.execute(stmt).scalars().all()
		count = len(expired)
		for token in expired:
			self.db.delete(token)
		self.db.commit()
		return count

