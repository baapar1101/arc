"""
Repository برای عملیات پایگاه داده مربوط به پروژه‌ها
"""

from sqlalchemy.orm import Session, joinedload
from sqlalchemy import and_, or_, func
from adapters.db.models.project import Project
from typing import List, Optional, Dict, Any, Tuple


class ProjectRepository:
	"""Repository برای مدیریت پروژه‌ها"""
	
	def __init__(self, db: Session):
		self.db = db
	
	def get_by_id(self, project_id: int, load_relations: bool = False) -> Optional[Project]:
		"""دریافت پروژه با ID"""
		query = self.db.query(Project).filter(Project.id == project_id)
		
		if load_relations:
			query = query.options(
				joinedload(Project.currency),
				joinedload(Project.manager),
				joinedload(Project.person),
				joinedload(Project.created_by)
			)
		
		return query.first()
	
	def get_by_business_and_code(self, business_id: int, code: str) -> Optional[Project]:
		"""دریافت پروژه با کسب‌وکار و کد"""
		return self.db.query(Project).filter(
			and_(
				Project.business_id == business_id,
				Project.code == code
			)
		).first()
	
	def list_by_business(
		self,
		business_id: int,
		is_active: Optional[bool] = None,
		status: Optional[str] = None,
		skip: int = 0,
		limit: int = 100
	) -> List[Project]:
		"""لیست پروژه‌های یک کسب‌وکار"""
		query = self.db.query(Project).filter(Project.business_id == business_id)
		
		if is_active is not None:
			query = query.filter(Project.is_active == is_active)
		
		if status:
			query = query.filter(Project.status == status)
		
		return query.order_by(Project.created_at.desc()).offset(skip).limit(limit).all()
	
	def search(
		self,
		business_id: int,
		search_term: Optional[str] = None,
		filters: Optional[Dict[str, Any]] = None,
		skip: int = 0,
		limit: int = 100
	) -> Tuple[List[Project], int]:
		"""جستجوی پروژه‌ها با فیلترها"""
		query = self.db.query(Project).filter(Project.business_id == business_id)
		
		# جستجوی متنی
		if search_term:
			search_pattern = f"%{search_term}%"
			query = query.filter(
				or_(
					Project.name.like(search_pattern),
					Project.code.like(search_pattern),
					Project.description.like(search_pattern)
				)
			)
		
		# فیلترها
		if filters:
			if 'status' in filters:
				if isinstance(filters['status'], list):
					query = query.filter(Project.status.in_(filters['status']))
				else:
					query = query.filter(Project.status == filters['status'])
			
			if 'is_active' in filters:
				query = query.filter(Project.is_active == filters['is_active'])
			
			if 'person_id' in filters:
				query = query.filter(Project.person_id == filters['person_id'])
			
			if 'manager_user_id' in filters:
				query = query.filter(Project.manager_user_id == filters['manager_user_id'])
			
			if 'currency_id' in filters:
				query = query.filter(Project.currency_id == filters['currency_id'])
			
			# فیلتر تاریخی
			if 'start_date_from' in filters and filters['start_date_from']:
				query = query.filter(Project.start_date >= filters['start_date_from'])
			
			if 'start_date_to' in filters and filters['start_date_to']:
				query = query.filter(Project.start_date <= filters['start_date_to'])
			
			if 'end_date_from' in filters and filters['end_date_from']:
				query = query.filter(Project.end_date >= filters['end_date_from'])
			
			if 'end_date_to' in filters and filters['end_date_to']:
				query = query.filter(Project.end_date <= filters['end_date_to'])
		
		# شمارش کل
		total = query.count()
		
		# اعمال محدودیت و offset
		items = query.order_by(Project.created_at.desc()).offset(skip).limit(limit).all()
		
		return items, total
	
	def count_by_business(self, business_id: int, is_active: Optional[bool] = None) -> int:
		"""شمارش پروژه‌های یک کسب‌وکار"""
		query = self.db.query(func.count(Project.id)).filter(Project.business_id == business_id)
		
		if is_active is not None:
			query = query.filter(Project.is_active == is_active)
		
		return query.scalar() or 0
	
	def create(self, project: Project) -> Project:
		"""ایجاد پروژه جدید"""
		self.db.add(project)
		self.db.flush()
		return project
	
	def update(self, project: Project) -> Project:
		"""به‌روزرسانی پروژه"""
		self.db.flush()
		return project
	
	def delete(self, project: Project) -> None:
		"""حذف پروژه (soft delete)"""
		project.is_active = False
		self.db.flush()
	
	def hard_delete(self, project: Project) -> None:
		"""حذف کامل پروژه"""
		self.db.delete(project)
		self.db.flush()

