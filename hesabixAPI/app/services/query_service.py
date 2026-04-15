from __future__ import annotations

from typing import Any, Type, TypeVar
from sqlalchemy import select, func, or_, and_
from sqlalchemy.orm import Session
from sqlalchemy.sql import Select

from adapters.api.v1.schemas import QueryInfo, FilterItem
from app.services.sort_resolution import effective_sort_specs

T = TypeVar('T')


class QueryBuilder:
	"""سرویس برای ساخت کوئری‌های دینامیک بر اساس QueryInfo"""
	
	def __init__(self, model_class: Type[T], db_session: Session) -> None:
		self.model_class = model_class
		self.db = db_session
		self.stmt: Select = select(model_class)
	
	def apply_filters(self, filters: list[FilterItem] | None) -> 'QueryBuilder':
		"""اعمال فیلترها بر روی کوئری"""
		if not filters:
			return self
		
		conditions = []
		for filter_item in filters:
			try:
				column = getattr(self.model_class, filter_item.property)
				condition = self._build_condition(column, filter_item.operator, filter_item.value)
				conditions.append(condition)
			except AttributeError:
				# اگر فیلد وجود نداشته باشد، آن را نادیده بگیر
				continue
		
		if conditions:
			self.stmt = self.stmt.where(and_(*conditions))
		
		return self
	
	def apply_search(self, search: str | None, search_fields: list[str] | None) -> 'QueryBuilder':
		"""اعمال جستجو بر روی فیلدهای مشخص شده"""
		if not search or not search_fields:
			return self
		
		conditions = []
		for field in search_fields:
			try:
				column = getattr(self.model_class, field)
				conditions.append(column.ilike(f"%{search}%"))
			except AttributeError:
				# اگر فیلد وجود نداشته باشد، آن را نادیده بگیر
				continue
		
		if conditions:
			self.stmt = self.stmt.where(or_(*conditions))
		
		return self
	
	def apply_sorting(self, sort_by: str | None, sort_desc: bool) -> 'QueryBuilder':
		"""اعمال مرتب‌سازی تک‌ستونه (سازگار با نسخهٔ قبلی)."""
		if not sort_by:
			return self
		
		try:
			column = getattr(self.model_class, sort_by)
			if sort_desc:
				self.stmt = self.stmt.order_by(column.desc())
			else:
				self.stmt = self.stmt.order_by(column.asc())
		except AttributeError:
			# اگر فیلد وجود نداشته باشد، مرتب‌سازی را نادیده بگیر
			pass
		
		return self
	
	def apply_sorting_from_query_info(self, query_info: QueryInfo) -> 'QueryBuilder':
		"""مرتب‌سازی از QueryInfo: آرایه sort در اولویت، وگرنه sort_by/sort_desc؛ فقط ستون‌های موجود روی مدل."""
		specs = effective_sort_specs(query_info, allowed=None, default_when_empty=None)
		if not specs:
			return self
		order_parts = []
		for name, desc in specs:
			if not hasattr(self.model_class, name):
				continue
			column = getattr(self.model_class, name)
			order_parts.append(column.desc() if desc else column.asc())
		if order_parts:
			self.stmt = self.stmt.order_by(*order_parts)
		return self
	
	def apply_pagination(self, skip: int, take: int) -> 'QueryBuilder':
		"""اعمال صفحه‌بندی بر روی کوئری"""
		self.stmt = self.stmt.offset(skip).limit(take)
		return self
	
	def apply_query_info(self, query_info: QueryInfo) -> 'QueryBuilder':
		"""اعمال تمام تنظیمات QueryInfo بر روی کوئری"""
		return (self
			.apply_filters(query_info.filters)
			.apply_search(query_info.search, query_info.search_fields)
			.apply_sorting_from_query_info(query_info)
			.apply_pagination(query_info.skip, query_info.take))
	
	def _build_condition(self, column, operator: str, value: Any):
		"""ساخت شرط بر اساس عملگر و مقدار"""
		if operator == "=":
			return column == value
		elif operator == ">":
			return column > value
		elif operator == ">=":
			return column >= value
		elif operator == "<":
			return column < value
		elif operator == "<=":
			return column <= value
		elif operator == "!=":
			return column != value
		elif operator == "*":  # contains
			return column.ilike(f"%{value}%")
		elif operator == "?*":  # ends with
			return column.ilike(f"%{value}")
		elif operator == "*?":  # starts with
			return column.ilike(f"{value}%")
		elif operator == "in":
			if not isinstance(value, list):
				raise ValueError("برای عملگر 'in' مقدار باید آرایه باشد")
			return column.in_(value)
		else:
			raise ValueError(f"عملگر پشتیبانی نشده: {operator}")
	
	def get_count_query(self) -> Select:
		"""دریافت کوئری شمارش (بدون pagination)"""
		return select(func.count()).select_from(self.stmt.subquery())
	
	def execute(self) -> list[T]:
		"""اجرای کوئری و بازگرداندن نتایج"""
		return list(self.db.execute(self.stmt).scalars().all())
	
	def execute_count(self) -> int:
		"""اجرای کوئری شمارش"""
		count_stmt = self.get_count_query()
		return int(self.db.execute(count_stmt).scalar() or 0)


class QueryService:
	"""سرویس اصلی برای مدیریت کوئری‌های فیلتر شده"""
	
	@staticmethod
	def query_with_filters(
		model_class: Type[T], 
		db: Session, 
		query_info: QueryInfo
	) -> tuple[list[T], int]:
		"""
	اجرای کوئری با فیلتر و بازگرداندن نتایج و تعداد کل
		
		Args:
			model_class: کلاس مدل SQLAlchemy
			db: جلسه پایگاه داده
			query_info: اطلاعات کوئری شامل فیلترها، مرتب‌سازی و صفحه‌بندی
		
		Returns:
			tuple: (لیست نتایج, تعداد کل رکوردها)
		"""
		# کوئری شمارش (بدون pagination)
		count_builder = QueryBuilder(model_class, db)
		count_builder.apply_filters(query_info.filters)
		count_builder.apply_search(query_info.search, query_info.search_fields)
		total_count = count_builder.execute_count()
		
		# کوئری داده‌ها (با pagination)
		data_builder = QueryBuilder(model_class, db)
		data_builder.apply_query_info(query_info)
		results = data_builder.execute()
		
		return results, total_count
