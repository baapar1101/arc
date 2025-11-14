from __future__ import annotations

from typing import Optional

from sqlalchemy import select, func, and_, or_
from sqlalchemy.orm import Session

from adapters.db.models.user import User
from adapters.db.repositories.base_repo import BaseRepository
from adapters.api.v1.schemas import QueryInfo


class UserRepository(BaseRepository[User]):
	def __init__(self, db: Session) -> None:
		super().__init__(db, User)

	def get_by_email(self, email: str) -> Optional[User]:
		stmt = select(User).where(User.email == email)
		return self.db.execute(stmt).scalars().first()

	def get_by_mobile(self, mobile: str) -> Optional[User]:
		stmt = select(User).where(User.mobile == mobile)
		return self.db.execute(stmt).scalars().first()

	def get_by_referral_code(self, referral_code: str) -> Optional[User]:
		stmt = select(User).where(User.referral_code == referral_code)
		return self.db.execute(stmt).scalars().first()

	def is_first_user(self) -> bool:
		"""بررسی اینکه آیا این اولین کاربر سیستم است یا نه"""
		stmt = select(func.count()).select_from(User)
		count = self.db.execute(stmt).scalar() or 0
		return count == 0

	def create(self, *, email: str | None, mobile: str | None, password_hash: str, first_name: str | None, last_name: str | None, referral_code: str, referred_by_user_id: int | None = None) -> User:
		# تعیین دسترسی‌های برنامه بر اساس اینکه آیا کاربر اول است یا نه
		app_permissions = {"superadmin": True} if self.is_first_user() else {}
		
		user = User(
			email=email, 
			mobile=mobile, 
			password_hash=password_hash, 
			first_name=first_name, 
			last_name=last_name, 
			referral_code=referral_code, 
			referred_by_user_id=referred_by_user_id,
			app_permissions=app_permissions
		)
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
	
	def to_dict(self, user: User) -> dict:
		"""تبدیل User object به dictionary برای API response"""
		return {
			"id": user.id,
			"email": user.email,
			"mobile": user.mobile,
			"first_name": user.first_name,
			"last_name": user.last_name,
			"is_active": user.is_active,
			"referral_code": user.referral_code,
			"referred_by_user_id": user.referred_by_user_id,
			"app_permissions": user.app_permissions,
			"created_at": user.created_at,
			"updated_at": user.updated_at,
			"signature_file_id": getattr(user, "signature_file_id", None),
		}


