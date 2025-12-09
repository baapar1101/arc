from __future__ import annotations

from typing import Optional, List

from sqlalchemy import select, func, and_, or_, text
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

	def create(self, *, email: str | None, mobile: str | None, password_hash: str, first_name: str | None, last_name: str | None, referral_code: str, referred_by_user_id: int | None = None, email_verified: bool = False) -> User:
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
			app_permissions=app_permissions,
			email_verified=email_verified
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
	
	def get_support_operators(self) -> List[User]:
		"""دریافت لیست تمام اپراتورهای پشتیبانی فعال"""
		stmt = select(User).where(
			text("JSON_EXTRACT(app_permissions, '$.support_operator') = true")
		).where(User.is_active == True)
		return list(self.db.execute(stmt).scalars().all())
	
	def is_support_operator(self, user_id: int) -> bool:
		"""بررسی اینکه آیا کاربر یک اپراتور پشتیبانی است یا نه"""
		user = self.get_by_id(user_id)
		if not user or not user.is_active:
			return False
		if not user.app_permissions:
			return False
		# SuperAdmin هم می‌تواند اپراتور باشد
		return bool(user.app_permissions.get("support_operator", False) or user.app_permissions.get("superadmin", False))
	
	def to_dict(self, user: User, include_extended: bool = False) -> dict:
		"""تبدیل User object به dictionary برای API response"""
		# ساخت full_name
		full_name = None
		if user.first_name or user.last_name:
			parts = [p for p in [user.first_name, user.last_name] if p]
			full_name = " ".join(parts) if parts else None
		
		# تعیین status از is_active
		status = "active" if user.is_active else "inactive"
		
		# تعیین role از app_permissions
		role = "user"
		if user.app_permissions:
			if user.app_permissions.get("superadmin"):
				role = "admin"
			elif user.app_permissions.get("operator"):
				role = "operator"
			elif user.app_permissions.get("supervisor"):
				role = "supervisor"
		
		# شمارش کسب‌وکارها
		businesses_count = 0
		last_login_ip = None
		last_login_at = None
		
		if include_extended:
			from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
			from adapters.db.repositories.business_repo import BusinessRepository
			from adapters.db.repositories.api_key_repo import ApiKeyRepository
			
			# شمارش کسب‌وکارها (هم مالک و هم عضو)
			business_repo = BusinessRepository(self.db)
			bp_repo = BusinessPermissionRepository(self.db)
			
			# دریافت کسب‌وکارهایی که کاربر مالک آن‌هاست
			owned_businesses = business_repo.get_by_owner_id(user.id)
			owned_business_ids = {b.id for b in owned_businesses}
			
			# دریافت کسب‌وکارهایی که کاربر عضو آن‌هاست (از طریق BusinessPermission با join=True)
			member_permissions = bp_repo.get_user_member_businesses(user.id)
			member_business_ids = {perm.business_id for perm in member_permissions}
			
			# ترکیب و حذف تکراری
			all_business_ids = owned_business_ids | member_business_ids
			businesses_count = len(all_business_ids)
			
			# آخرین ورود
			api_repo = ApiKeyRepository(self.db)
			from sqlalchemy import select, desc
			from adapters.db.models.api_key import ApiKey
			stmt = select(ApiKey).where(
				ApiKey.user_id == user.id,
				ApiKey.revoked_at.is_(None)
			).order_by(desc(ApiKey.last_used_at)).limit(1)
			last_key = self.db.execute(stmt).scalars().first()
			if last_key:
				last_login_ip = last_key.ip
				last_login_at = last_key.last_used_at or last_key.created_at
		
		result = {
			"id": user.id,
			"email": user.email,
			"mobile": user.mobile,
			"first_name": user.first_name,
			"last_name": user.last_name,
			"full_name": full_name,
			"is_active": user.is_active,
			"status": status,
			"role": role,
			"referral_code": user.referral_code,
			"referred_by_user_id": user.referred_by_user_id,
			"app_permissions": user.app_permissions,
			"created_at": user.created_at,
			"updated_at": user.updated_at,
			"signature_file_id": getattr(user, "signature_file_id", None),
		}
		
		if include_extended:
			result.update({
				"businesses_count": businesses_count,
				"last_login_ip": last_login_ip,
				"last_login_at": last_login_at,
			})
		
		return result


