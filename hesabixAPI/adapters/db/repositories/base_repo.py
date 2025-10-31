from __future__ import annotations

from typing import Type, TypeVar, Generic, Any
from sqlalchemy.orm import Session
from sqlalchemy import select, func

from app.services.query_service import QueryService
from adapters.api.v1.schemas import QueryInfo

T = TypeVar('T')


class BaseRepository(Generic[T]):
	"""کلاس پایه برای Repository ها با قابلیت فیلتر پیشرفته"""
	
	def __init__(self, db: Session, model_class: Type[T]) -> None:
		self.db = db
		self.model_class = model_class
	
	def query_with_filters(self, query_info: QueryInfo) -> tuple[list[T], int]:
		"""
	اجرای کوئری با فیلتر و بازگرداندن نتایج و تعداد کل
		
		Args:
			query_info: اطلاعات کوئری شامل فیلترها، مرتب‌سازی و صفحه‌بندی
		
		Returns:
			tuple: (لیست نتایج, تعداد کل رکوردها)
		"""
		return QueryService.query_with_filters(self.model_class, self.db, query_info)
	
	def get_by_id(self, id: int) -> T | None:
		"""دریافت رکورد بر اساس ID"""
		stmt = select(self.model_class).where(self.model_class.id == id)
		return self.db.execute(stmt).scalars().first()
	
	def get_all(self, limit: int = 100, offset: int = 0) -> list[T]:
		"""دریافت تمام رکوردها با محدودیت"""
		stmt = select(self.model_class).offset(offset).limit(limit)
		return list(self.db.execute(stmt).scalars().all())
	
	def count_all(self) -> int:
		"""شمارش تمام رکوردها"""
		stmt = select(func.count()).select_from(self.model_class)
		return int(self.db.execute(stmt).scalar() or 0)
	
	def exists(self, **filters) -> bool:
		"""بررسی وجود رکورد بر اساس فیلترهای مشخص شده"""
		stmt = select(self.model_class)
		for field, value in filters.items():
			if hasattr(self.model_class, field):
				column = getattr(self.model_class, field)
				stmt = stmt.where(column == value)
		
		return self.db.execute(stmt).scalars().first() is not None
	
	def delete(self, obj: T) -> None:
		"""حذف رکورد از دیتابیس"""
		self.db.delete(obj)
		self.db.commit()
	
	def update(self, obj: T) -> T:
		"""بروزرسانی رکورد در دیتابیس و برگرداندن شیء تازه‌سازی شده"""
		self.db.commit()
		self.db.refresh(obj)
		return obj