from __future__ import annotations

from datetime import datetime, timedelta
from typing import Optional

from sqlalchemy import select, and_
from sqlalchemy.orm import Session

from adapters.db.models.mobile_verification import MobileVerificationToken


class MobileVerificationRepository:
	def __init__(self, db: Session) -> None:
		self.db = db
	
	def create(
		self,
		*,
		user_id: int,
		mobile: str,
		otp_code_hash: str,
		expires_at: datetime,
		commit: bool = True,
	) -> MobileVerificationToken:
		obj = MobileVerificationToken(
			user_id=user_id,
			mobile=mobile,
			otp_code_hash=otp_code_hash,
			expires_at=expires_at,
			attempts=0,
		)
		self.db.add(obj)
		if commit:
			self.db.commit()
		else:
			self.db.flush()
		self.db.refresh(obj)
		return obj
	
	def get_active_by_user(self, user_id: int) -> Optional[MobileVerificationToken]:
		"""دریافت آخرین token فعال کاربر"""
		stmt = select(MobileVerificationToken).where(
			and_(
				MobileVerificationToken.user_id == user_id,
				MobileVerificationToken.verified_at.is_(None),
				MobileVerificationToken.expires_at > datetime.utcnow()
			)
		).order_by(MobileVerificationToken.created_at.desc())
		return self.db.execute(stmt).scalars().first()
	
	def get_by_hash(self, otp_code_hash: str) -> Optional[MobileVerificationToken]:
		"""دریافت token با hash OTP"""
		stmt = select(MobileVerificationToken).where(
			and_(
				MobileVerificationToken.otp_code_hash == otp_code_hash,
				MobileVerificationToken.verified_at.is_(None),
				MobileVerificationToken.expires_at > datetime.utcnow()
			)
		).order_by(MobileVerificationToken.created_at.desc())
		return self.db.execute(stmt).scalars().first()
	
	def count_recent_by_user(self, user_id: int, hours: int = 1) -> int:
		"""شمارش token های ایجاد شده در N ساعت اخیر"""
		cutoff = datetime.utcnow() - timedelta(hours=hours)
		stmt = select(MobileVerificationToken).where(
			and_(
				MobileVerificationToken.user_id == user_id,
				MobileVerificationToken.created_at >= cutoff
			)
		)
		return len(self.db.execute(stmt).scalars().all())
	
	def increment_attempts(self, token: MobileVerificationToken) -> None:
		"""افزایش تعداد تلاش‌های ناموفق"""
		token.attempts = token.attempts + 1
		self.db.add(token)
		self.db.commit()
	
	def mark_verified(self, token: MobileVerificationToken) -> None:
		"""علامت‌گذاری token به عنوان تایید شده"""
		token.verified_at = datetime.utcnow()
		self.db.add(token)
		self.db.commit()
	
	def delete_expired(self) -> int:
		"""حذف token های منقضی شده (قدیمی‌تر از 7 روز)"""
		cutoff = datetime.utcnow() - timedelta(days=7)
		stmt = select(MobileVerificationToken).where(
			MobileVerificationToken.expires_at < cutoff
		)
		expired = self.db.execute(stmt).scalars().all()
		count = len(expired)
		for token in expired:
			self.db.delete(token)
		self.db.commit()
		return count

