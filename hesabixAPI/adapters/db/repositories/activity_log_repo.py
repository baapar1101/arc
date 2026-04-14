from __future__ import annotations

from typing import List, Optional, Union
from datetime import datetime
from sqlalchemy.orm import Session
from sqlalchemy import and_, desc, func

from adapters.db.models.activity_log import ActivityLog
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

