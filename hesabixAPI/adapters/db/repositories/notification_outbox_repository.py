from __future__ import annotations

from typing import Optional, List
from datetime import datetime
from sqlalchemy import select, and_, func, or_
from sqlalchemy.orm import Session

from adapters.db.models.notification import NotificationOutbox
from adapters.db.repositories.base_repo import BaseRepository
from adapters.api.v1.schemas import QueryInfo, FilterItem


class NotificationOutboxRepository(BaseRepository[NotificationOutbox]):
	"""Repository برای مدیریت NotificationOutbox"""
	
	def __init__(self, db: Session) -> None:
		super().__init__(db, NotificationOutbox)
	
	def list_for_user(
		self,
		user_id: int,
		query_info: QueryInfo
	) -> tuple[List[NotificationOutbox], int]:
		"""
		دریافت لیست ناتیفیکیشن‌های کاربر با فیلتر و صفحه‌بندی
		
		Args:
			user_id: شناسه کاربر
			query_info: اطلاعات کوئری شامل فیلترها، مرتب‌سازی و صفحه‌بندی
		
		Returns:
			tuple: (لیست ناتیفیکیشن‌ها, تعداد کل)
		"""
		# ایجاد یک QueryInfo جدید با فیلتر user_id
		# مهم: حذف هرگونه فیلتر user_id که کاربر ارسال کرده (برای امنیت)
		# و اضافه کردن فیلتر user_id واقعی کاربر
		filters = []
		if query_info.filters:
			# حذف فیلترهای user_id که کاربر ارسال کرده (امنیت)
			filters = [
				f for f in query_info.filters 
				if f.property != "user_id"
			]
		
		# اضافه کردن فیلتر user_id واقعی (همیشه اعمال می‌شود)
		filters.append(FilterItem(
			property="user_id",
			operator="=",
			value=user_id
		))
		
		# ایجاد QueryInfo جدید با فیلترهای اصلاح شده
		secure_query_info = QueryInfo(
			sort_by=query_info.sort_by,
			sort_desc=query_info.sort_desc,
			take=query_info.take,
			skip=query_info.skip,
			search=query_info.search,
			search_fields=query_info.search_fields,
			filters=filters,
			include_inventory=query_info.include_inventory,
			inventory_as_of_date=query_info.inventory_as_of_date,
		)
		
		# استفاده از متد query_with_filters از BaseRepository
		return self.query_with_filters(secure_query_info)
	
	def get_by_id_for_user(self, notification_id: int, user_id: int) -> Optional[NotificationOutbox]:
		"""دریافت یک ناتیفیکیشن بر اساس ID و user_id (برای امنیت)"""
		stmt = select(NotificationOutbox).where(
			and_(
				NotificationOutbox.id == notification_id,
				NotificationOutbox.user_id == user_id
			)
		)
		return self.db.execute(stmt).scalars().first()
	
	def count_for_user(
		self,
		user_id: int,
		channel: Optional[str] = None,
		event_key: Optional[str] = None,
		status: Optional[str] = None,
		from_date: Optional[datetime] = None,
		to_date: Optional[datetime] = None
	) -> int:
		"""شمارش ناتیفیکیشن‌های کاربر با فیلترهای اختیاری"""
		stmt = select(func.count()).select_from(NotificationOutbox).where(
			NotificationOutbox.user_id == user_id
		)
		
		if channel:
			stmt = stmt.where(NotificationOutbox.channel == channel)
		if event_key:
			stmt = stmt.where(NotificationOutbox.event_key == event_key)
		if status:
			stmt = stmt.where(NotificationOutbox.status == status)
		if from_date:
			stmt = stmt.where(NotificationOutbox.created_at >= from_date)
		if to_date:
			stmt = stmt.where(NotificationOutbox.created_at <= to_date)
		
		return int(self.db.execute(stmt).scalar() or 0)

