from __future__ import annotations

from typing import List, Optional, Tuple, Union
from datetime import datetime
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import and_, asc, desc, func, or_

from adapters.db.models.activity_log import ActivityLog
from adapters.db.models.business import Business
from adapters.db.models.user import User
from adapters.db.repositories.base_repo import BaseRepository


class ActivityLogRepository(BaseRepository[ActivityLog]):
	def __init__(self, db: Session) -> None:
		super().__init__(db, ActivityLog)
	
	def get_by_business(
		self,
		business_id: int,
		category: Optional[str] = None,
		entity_type: Optional[str] = None,
		start_date: Optional[datetime] = None,
		end_date: Optional[datetime] = None,
		limit: int = 100,
		offset: int = 0
	) -> List[ActivityLog]:
		"""دریافت لاگ‌های یک کسب و کار با فیلتر"""
		query = self.db.query(ActivityLog).filter(
			ActivityLog.business_id == business_id
		)
		
		if category:
			query = query.filter(ActivityLog.category == category)
		if entity_type:
			query = query.filter(ActivityLog.entity_type == entity_type)
		if start_date:
			query = query.filter(ActivityLog.created_at >= start_date)
		if end_date:
			query = query.filter(ActivityLog.created_at <= end_date)
		
		return query.order_by(desc(ActivityLog.created_at)).limit(limit).offset(offset).all()
	
	def count_by_business(
		self,
		business_id: int,
		category: Optional[str] = None,
		entity_type: Optional[str] = None,
		start_date: Optional[datetime] = None,
		end_date: Optional[datetime] = None
	) -> int:
		"""شمارش لاگ‌های یک کسب و کار"""
		query = self.db.query(func.count(ActivityLog.id)).filter(
			ActivityLog.business_id == business_id
		)
		
		if category:
			query = query.filter(ActivityLog.category == category)
		if entity_type:
			query = query.filter(ActivityLog.entity_type == entity_type)
		if start_date:
			query = query.filter(ActivityLog.created_at >= start_date)
		if end_date:
			query = query.filter(ActivityLog.created_at <= end_date)
		
		return query.scalar() or 0
	
	def get_by_user(
		self,
		user_id: int,
		business_id: Optional[int] = None,
		limit: int = 100,
		offset: int = 0
	) -> List[ActivityLog]:
		"""دریافت لاگ‌های یک کاربر"""
		query = self.db.query(ActivityLog).filter(
			ActivityLog.user_id == user_id
		)
		
		if business_id:
			query = query.filter(ActivityLog.business_id == business_id)
		
		return query.order_by(desc(ActivityLog.created_at)).limit(limit).offset(offset).all()
	
	def get_by_entity(
		self,
		entity_type: str,
		entity_id: Union[int, str],
		business_id: Optional[int] = None
	) -> List[ActivityLog]:
		"""دریافت تاریخچه تغییرات یک موجودیت"""
		# تبدیل entity_id به string برای مقایسه (برای پشتیبانی از UUID)
		entity_id_str = str(entity_id) if entity_id is not None else None
		
		query = self.db.query(ActivityLog).filter(
			and_(
				ActivityLog.entity_type == entity_type,
				ActivityLog.entity_id == entity_id_str
			)
		)
		
		if business_id:
			query = query.filter(ActivityLog.business_id == business_id)
		
		return query.order_by(desc(ActivityLog.created_at)).all()

	# ---------------------------------------------------------------
	# Admin/Superadmin queries — جستجوی سراسری با فیلترهای کامل
	# ---------------------------------------------------------------
	# ستون‌های مجاز برای sort تا از SQL injection و خطای ستون نامعتبر جلوگیری شود.
	_ADMIN_SORTABLE_COLUMNS = {
		"id": ActivityLog.id,
		"created_at": ActivityLog.created_at,
		"business_id": ActivityLog.business_id,
		"user_id": ActivityLog.user_id,
		"category": ActivityLog.category,
		"action": ActivityLog.action,
		"entity_type": ActivityLog.entity_type,
	}

	def _build_admin_filters(
		self,
		query,
		business_id: Optional[int] = None,
		user_id: Optional[int] = None,
		category: Optional[str] = None,
		action: Optional[str] = None,
		entity_type: Optional[str] = None,
		start_date: Optional[datetime] = None,
		end_date: Optional[datetime] = None,
		search: Optional[str] = None,
	):
		"""ساخت WHERE های مشترک بین get_admin و count_admin."""
		if business_id is not None:
			query = query.filter(ActivityLog.business_id == business_id)
		if user_id is not None:
			query = query.filter(ActivityLog.user_id == user_id)
		if category:
			query = query.filter(ActivityLog.category == category)
		if action:
			query = query.filter(ActivityLog.action == action)
		if entity_type:
			query = query.filter(ActivityLog.entity_type == entity_type)
		if start_date:
			query = query.filter(ActivityLog.created_at >= start_date)
		if end_date:
			query = query.filter(ActivityLog.created_at <= end_date)
		if search:
			like = f"%{search.strip()}%"
			query = query.filter(
				or_(
					ActivityLog.description.ilike(like),
					ActivityLog.entity_id.ilike(like),
				)
			)
		return query

	def get_admin(
		self,
		business_id: Optional[int] = None,
		user_id: Optional[int] = None,
		category: Optional[str] = None,
		action: Optional[str] = None,
		entity_type: Optional[str] = None,
		start_date: Optional[datetime] = None,
		end_date: Optional[datetime] = None,
		search: Optional[str] = None,
		sort_by: str = "created_at",
		sort_desc: bool = True,
		limit: int = 50,
		offset: int = 0,
	) -> List[ActivityLog]:
		"""دریافت لاگ‌های سراسری برای پنل ادمین با Eager loading روابط."""
		query = self.db.query(ActivityLog).options(
			joinedload(ActivityLog.user),
			joinedload(ActivityLog.business),
		)
		query = self._build_admin_filters(
			query,
			business_id=business_id,
			user_id=user_id,
			category=category,
			action=action,
			entity_type=entity_type,
			start_date=start_date,
			end_date=end_date,
			search=search,
		)

		# امن‌سازی sort
		sort_col = self._ADMIN_SORTABLE_COLUMNS.get(sort_by, ActivityLog.created_at)
		order = desc(sort_col) if sort_desc else asc(sort_col)
		# tie-breaker پایدار با id برای جلوگیری از پرش ردیف در صفحه‌بندی هنگام تساوی sort
		query = query.order_by(order, desc(ActivityLog.id))

		return query.limit(limit).offset(offset).all()

	def count_admin(
		self,
		business_id: Optional[int] = None,
		user_id: Optional[int] = None,
		category: Optional[str] = None,
		action: Optional[str] = None,
		entity_type: Optional[str] = None,
		start_date: Optional[datetime] = None,
		end_date: Optional[datetime] = None,
		search: Optional[str] = None,
	) -> int:
		"""شمارش لاگ‌های منطبق برای total در صفحه‌بندی سرور."""
		query = self.db.query(func.count(ActivityLog.id))
		query = self._build_admin_filters(
			query,
			business_id=business_id,
			user_id=user_id,
			category=category,
			action=action,
			entity_type=entity_type,
			start_date=start_date,
			end_date=end_date,
			search=search,
		)
		return int(query.scalar() or 0)

	def search_businesses(
		self,
		query_text: Optional[str] = None,
		limit: int = 20,
	) -> List[Business]:
		"""جستجوی کسب‌وکارها برای autocomplete فیلتر."""
		q = self.db.query(Business)
		if query_text:
			like = f"%{query_text.strip()}%"
			q = q.filter(Business.name.ilike(like))
		return q.order_by(asc(Business.name)).limit(limit).all()

	def search_users(
		self,
		query_text: Optional[str] = None,
		business_id: Optional[int] = None,
		limit: int = 20,
	) -> List[Tuple[User, Optional[str]]]:
		"""جستجوی کاربران (سراسری یا محدود به اعضای یک کسب‌وکار) برای autocomplete.

		اگر business_id بدهیم، اتحاد owner و BusinessPermission بازگردانده می‌شود.
		"""
		# Lazy import برای پرهیز از حلقه import
		from adapters.db.models.business_permission import BusinessPermission

		# اتحاد user_idهای مجاز
		if business_id is not None:
			# Subquery: همهٔ user_idهای مرتبط با این کسب‌وکار (مالک + اعضای دارای مجوز)
			perm_users = self.db.query(BusinessPermission.user_id).filter(
				BusinessPermission.business_id == business_id
			)
			owner_user = self.db.query(Business.owner_id).filter(Business.id == business_id)
			allowed_ids_subq = perm_users.union(owner_user).subquery()
			q = self.db.query(User).filter(User.id.in_(allowed_ids_subq))
		else:
			q = self.db.query(User).filter(User.is_active == True)  # noqa: E712

		if query_text:
			like = f"%{query_text.strip()}%"
			q = q.filter(
				or_(
					User.first_name.ilike(like),
					User.last_name.ilike(like),
					User.email.ilike(like),
					User.mobile.ilike(like),
				)
			)
		users = q.order_by(asc(User.first_name), asc(User.last_name)).limit(limit).all()
		return [(u, None) for u in users]

	def get_distinct_actions(self) -> List[str]:
		"""لیست actionهای موجود در لاگ‌ها برای dropdown."""
		rows = self.db.query(ActivityLog.action).distinct().order_by(asc(ActivityLog.action)).all()
		return [r[0] for r in rows if r[0]]

