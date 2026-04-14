from __future__ import annotations

from datetime import datetime, timedelta
from typing import Optional
from secrets import token_urlsafe

from sqlalchemy import select, and_
from sqlalchemy.orm import Session

from adapters.db.models.otp_login_session import OtpLoginSession


class OtpLoginRepository:
	def __init__(self, db: Session) -> None:
		self.db = db
	
	def generate_session_id(self) -> str:
		"""تولید session_id منحصر به فرد"""
		return token_urlsafe(32)
	
	def create(
		self,
		*,
		mobile: Optional[str] = None,
		email: Optional[str] = None,
		channel: str = "sms",
		otp_code_hash: str,
		expires_at: datetime,
		ip_address: Optional[str] = None,
		user_agent: Optional[str] = None
	) -> OtpLoginSession:
		session_id = self.generate_session_id()
		obj = OtpLoginSession(
			session_id=session_id,
			mobile=mobile,
			email=email,
			channel=channel,
			otp_code_hash=otp_code_hash,
			expires_at=expires_at,
			attempts=0,
			ip_address=ip_address,
			user_agent=user_agent,
		)
		self.db.add(obj)
		self.db.commit()
		self.db.refresh(obj)
		return obj
	
	def get_by_session_id(self, session_id: str) -> Optional[OtpLoginSession]:
		"""دریافت session با session_id"""
		stmt = select(OtpLoginSession).where(
			and_(
				OtpLoginSession.session_id == session_id,
				OtpLoginSession.verified_at.is_(None),
				OtpLoginSession.expires_at > datetime.utcnow()
			)
		)
		return self.db.execute(stmt).scalars().first()
	
	def count_recent_by_mobile(self, mobile: str, hours: int = 1) -> int:
		"""شمارش session های ایجاد شده در N ساعت اخیر برای یک شماره"""
		cutoff = datetime.utcnow() - timedelta(hours=hours)
		stmt = select(OtpLoginSession).where(
			and_(
				OtpLoginSession.mobile == mobile,
				OtpLoginSession.created_at >= cutoff
			)
		)
		return len(self.db.execute(stmt).scalars().all())
	
	def count_recent_by_email(self, email: str, hours: int = 1) -> int:
		"""شمارش session های ایجاد شده در N ساعت اخیر برای یک ایمیل"""
		cutoff = datetime.utcnow() - timedelta(hours=hours)
		stmt = select(OtpLoginSession).where(
			and_(
				OtpLoginSession.email == email,
				OtpLoginSession.created_at >= cutoff
			)
		)
		return len(self.db.execute(stmt).scalars().all())
	
	def count_recent_by_identifier(self, mobile: Optional[str] = None, email: Optional[str] = None, hours: int = 1) -> int:
		"""شمارش session های ایجاد شده در N ساعت اخیر برای یک identifier"""
		cutoff = datetime.utcnow() - timedelta(hours=hours)
		conditions = [OtpLoginSession.created_at >= cutoff]
		if mobile:
			conditions.append(OtpLoginSession.mobile == mobile)
		if email:
			conditions.append(OtpLoginSession.email == email)
		stmt = select(OtpLoginSession).where(and_(*conditions))
		return len(self.db.execute(stmt).scalars().all())
	
	def update_channel(self, session: OtpLoginSession, channel: str, otp_code_hash: str) -> None:
		"""به‌روزرسانی کانال و OTP برای session موجود"""
		session.channel = channel
		session.otp_code_hash = otp_code_hash
		session.last_otp_sent_at = datetime.utcnow()
		self.db.add(session)
		self.db.commit()
	
	def increment_attempts(self, session: OtpLoginSession) -> None:
		"""افزایش تعداد تلاش‌های ناموفق"""
		session.attempts = session.attempts + 1
		self.db.add(session)
		self.db.commit()
	
	def mark_verified(self, session: OtpLoginSession, user_id: int) -> None:
		"""علامت‌گذاری session به عنوان تایید شده"""
		session.verified_at = datetime.utcnow()
		session.user_id = user_id
		self.db.add(session)
		self.db.commit()
	
	def delete_expired(self) -> int:
		"""حذف session های منقضی شده (قدیمی‌تر از 24 ساعت)"""
		cutoff = datetime.utcnow() - timedelta(hours=24)
		stmt = select(OtpLoginSession).where(
			OtpLoginSession.expires_at < cutoff
		)
		expired = self.db.execute(stmt).scalars().all()
		count = len(expired)
		for session in expired:
			self.db.delete(session)
		self.db.commit()
		return count

