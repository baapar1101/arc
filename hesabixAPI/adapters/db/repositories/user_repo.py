from __future__ import annotations

from typing import Optional

from sqlalchemy import select, func, and_, or_
from sqlalchemy.orm import Session

from adapters.db.models.user import User


class UserRepository:
	def __init__(self, db: Session) -> None:
		self.db = db

	def get_by_email(self, email: str) -> Optional[User]:
		stmt = select(User).where(User.email == email)
		return self.db.execute(stmt).scalars().first()

	def get_by_mobile(self, mobile: str) -> Optional[User]:
		stmt = select(User).where(User.mobile == mobile)
		return self.db.execute(stmt).scalars().first()

	def get_by_referral_code(self, referral_code: str) -> Optional[User]:
		stmt = select(User).where(User.referral_code == referral_code)
		return self.db.execute(stmt).scalars().first()

	def create(self, *, email: str | None, mobile: str | None, password_hash: str, first_name: str | None, last_name: str | None, referral_code: str, referred_by_user_id: int | None = None) -> User:
		user = User(email=email, mobile=mobile, password_hash=password_hash, first_name=first_name, last_name=last_name, referral_code=referral_code, referred_by_user_id=referred_by_user_id)
		self.db.add(user)
		self.db.commit()
		self.db.refresh(user)
		return user

	def count_referred(self, referrer_user_id: int, start: str | None = None, end: str | None = None) -> int:
		stmt = select(func.count()).select_from(User).where(User.referred_by_user_id == referrer_user_id)
		if start is not None:
			stmt = stmt.where(User.created_at >= func.cast(start, User.created_at.type))
		if end is not None:
			stmt = stmt.where(User.created_at < func.cast(end, User.created_at.type))
		return int(self.db.execute(stmt).scalar() or 0)

	def count_referred_between(self, referrer_user_id: int, start_dt, end_dt) -> int:
		stmt = select(func.count()).select_from(User).where(
			and_(
				User.referred_by_user_id == referrer_user_id,
				User.created_at >= start_dt,
				User.created_at < end_dt,
			)
		)
		return int(self.db.execute(stmt).scalar() or 0)

	def count_referred_filtered(self, referrer_user_id: int, start_dt=None, end_dt=None, search: str | None = None) -> int:
		stmt = select(func.count()).select_from(User).where(User.referred_by_user_id == referrer_user_id)
		if start_dt is not None:
			stmt = stmt.where(User.created_at >= start_dt)
		if end_dt is not None:
			stmt = stmt.where(User.created_at < end_dt)
		if search:
			like = f"%{search}%"
			stmt = stmt.where(or_(User.first_name.ilike(like), User.last_name.ilike(like), User.email.ilike(like)))
		return int(self.db.execute(stmt).scalar() or 0)

	def list_referred(self, referrer_user_id: int, start_dt=None, end_dt=None, search: str | None = None, offset: int = 0, limit: int = 20):
		stmt = select(User).where(User.referred_by_user_id == referrer_user_id)
		if start_dt is not None:
			stmt = stmt.where(User.created_at >= start_dt)
		if end_dt is not None:
			stmt = stmt.where(User.created_at < end_dt)
		if search:
			like = f"%{search}%"
			stmt = stmt.where(or_(User.first_name.ilike(like), User.last_name.ilike(like), User.email.ilike(like)))
		stmt = stmt.order_by(User.created_at.desc()).offset(offset).limit(limit)
		return self.db.execute(stmt).scalars().all()


