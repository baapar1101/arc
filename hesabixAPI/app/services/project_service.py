"""
سرویس مدیریت پروژه‌ها
"""

from __future__ import annotations

from typing import Dict, Any, List, Optional, Tuple
from datetime import datetime, date, timezone
from decimal import Decimal
import logging

from sqlalchemy.orm import Session
from sqlalchemy import and_, func

from adapters.db.models.project import Project
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.business import Business
from adapters.db.models.currency import Currency
from adapters.db.models.user import User
from adapters.db.models.person import Person
from adapters.db.models.business_permission import BusinessPermission
from adapters.db.models.task_management import ProjectMember, Task, TaskStatus
from app.core.business_membership import membership_is_active
from adapters.db.repositories.project_repository import ProjectRepository
from app.core.responses import ApiError

logger = logging.getLogger(__name__)


def _parse_date(value: Any) -> Optional[date]:
	"""تبدیل مقدار به تاریخ"""
	if value is None:
		return None
	if isinstance(value, date):
		return value
	if isinstance(value, datetime):
		return value.date()
	if isinstance(value, str):
		try:
			return datetime.fromisoformat(value.replace('Z', '+00:00')).date()
		except Exception:
			return None
	return None


def create_project(
	db: Session,
	business_id: int,
	user_id: int,
	data: Dict[str, Any]
) -> Project:
	"""
	ایجاد پروژه جدید
	
	Args:
		db: نشست پایگاه داده
		business_id: شناسه کسب‌وکار
		user_id: شناسه کاربر ایجادکننده
		data: اطلاعات پروژه
	
	Returns:
		پروژه ایجاد شده
	"""
	# بررسی وجود کسب‌وکار
	business = db.query(Business).filter(Business.id == business_id).first()
	if not business:
		raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)
	
	# بررسی یکتا بودن کد
	code = data.get('code')
	if not code:
		raise ApiError("PROJECT_CODE_REQUIRED", "کد پروژه الزامی است", http_status=400)
	
	repo = ProjectRepository(db)
	existing = repo.get_by_business_and_code(business_id, code)
	if existing:
		raise ApiError("PROJECT_CODE_EXISTS", "کد پروژه تکراری است", http_status=400)
	
	# بررسی نام
	name = data.get('name')
	if not name:
		raise ApiError("PROJECT_NAME_REQUIRED", "نام پروژه الزامی است", http_status=400)
	
	# اعتبارسنجی ارز
	currency_id = data.get('currency_id')
	if currency_id:
		currency = db.query(Currency).filter(Currency.id == currency_id).first()
		if not currency:
			raise ApiError("CURRENCY_NOT_FOUND", "ارز یافت نشد", http_status=404)
	
	# اعتبارسنجی مدیر پروژه
	manager_user_id = data.get('manager_user_id')
	if manager_user_id:
		_business_member_user(db, business, manager_user_id)
	
	# اعتبارسنجی شخص
	person_id = data.get('person_id')
	if person_id:
		person = db.query(Person).filter(
			and_(Person.id == person_id, Person.business_id == business_id)
		).first()
		if not person:
			raise ApiError("PERSON_NOT_FOUND", "شخص یافت نشد", http_status=404)
	
	# ایجاد پروژه
	project = Project(
		business_id=business_id,
		code=code,
		name=name,
		description=data.get('description'),
		status=data.get('status', 'active'),
		start_date=_parse_date(data.get('start_date')),
		end_date=_parse_date(data.get('end_date')),
		budget=data.get('budget'),
		currency_id=currency_id,
		manager_user_id=manager_user_id,
		person_id=person_id,
		extra_info=data.get('extra_info', {}),
		is_active=data.get('is_active', True),
		created_by_user_id=user_id
	)
	
	db.add(project)
	db.flush()
	if manager_user_id:
		db.add(ProjectMember(
			business_id=business_id,
			project_id=project.id,
			user_id=manager_user_id,
			role="manager",
			added_by_user_id=user_id,
		))
	db.commit()
	db.refresh(project)
	
	logger.info(f"Project created: {project.id} - {project.name} (Business: {business_id})")
	
	return project


def update_project(
	db: Session,
	project_id: int,
	business_id: int,
	data: Dict[str, Any]
) -> Project:
	"""
	به‌روزرسانی پروژه
	
	Args:
		db: نشست پایگاه داده
		project_id: شناسه پروژه
		business_id: شناسه کسب‌وکار (برای امنیت)
		data: اطلاعات جدید
	
	Returns:
		پروژه به‌روزرسانی شده
	"""
	repo = ProjectRepository(db)
	project = repo.get_by_id(project_id)
	
	if not project:
		raise ApiError("PROJECT_NOT_FOUND", "پروژه یافت نشد", http_status=404)
	
	# بررسی دسترسی
	if project.business_id != business_id:
		raise ApiError("ACCESS_DENIED", "دسترسی به این پروژه ندارید", http_status=403)
	
	# بررسی یکتا بودن کد (در صورت تغییر)
	if 'code' in data and data['code'] != project.code:
		existing = repo.get_by_business_and_code(business_id, data['code'])
		if existing:
			raise ApiError("PROJECT_CODE_EXISTS", "کد پروژه تکراری است", http_status=400)
		project.code = data['code']
	
	# به‌روزرسانی فیلدها
	if 'name' in data:
		if not data['name']:
			raise ApiError("PROJECT_NAME_REQUIRED", "نام پروژه الزامی است", http_status=400)
		project.name = data['name']
	
	if 'description' in data:
		project.description = data['description']
	
	if 'status' in data:
		project.status = data['status']
	
	if 'start_date' in data:
		project.start_date = _parse_date(data['start_date'])
	
	if 'end_date' in data:
		project.end_date = _parse_date(data['end_date'])
	
	if 'budget' in data:
		project.budget = data['budget']
	
	if 'currency_id' in data:
		if data['currency_id']:
			currency = db.query(Currency).filter(Currency.id == data['currency_id']).first()
			if not currency:
				raise ApiError("CURRENCY_NOT_FOUND", "ارز یافت نشد", http_status=404)
		project.currency_id = data['currency_id']
	
	if 'manager_user_id' in data:
		new_manager_id = data['manager_user_id']
		business = db.get(Business, business_id)
		if not business:
			raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)
		if new_manager_id:
			_business_member_user(db, business, new_manager_id)
		old_manager_id = project.manager_user_id
		project.manager_user_id = new_manager_id
		if old_manager_id and old_manager_id != new_manager_id:
			old_member = db.query(ProjectMember).filter(
				ProjectMember.business_id == business_id,
				ProjectMember.project_id == project_id,
				ProjectMember.user_id == old_manager_id,
				ProjectMember.role == "manager",
			).first()
			if old_member:
				old_member.role = "member"
		if new_manager_id:
			manager_member = db.query(ProjectMember).filter(
				ProjectMember.business_id == business_id,
				ProjectMember.project_id == project_id,
				ProjectMember.user_id == new_manager_id,
			).first()
			if manager_member:
				manager_member.role = "manager"
			else:
				db.add(ProjectMember(
					business_id=business_id,
					project_id=project_id,
					user_id=new_manager_id,
					role="manager",
					added_by_user_id=new_manager_id,
				))
	
	if 'person_id' in data:
		if data['person_id']:
			person = db.query(Person).filter(
				and_(Person.id == data['person_id'], Person.business_id == business_id)
			).first()
			if not person:
				raise ApiError("PERSON_NOT_FOUND", "شخص یافت نشد", http_status=404)
		project.person_id = data['person_id']
	
	if 'extra_info' in data:
		project.extra_info = data['extra_info']
	
	if 'is_active' in data:
		project.is_active = data['is_active']
	
	db.commit()
	db.refresh(project)
	
	logger.info(f"Project updated: {project.id} - {project.name}")
	
	return project


def delete_project(
	db: Session,
	project_id: int,
	business_id: int,
	hard_delete: bool = False
) -> None:
	"""
	حذف پروژه
	
	Args:
		db: نشست پایگاه داده
		project_id: شناسه پروژه
		business_id: شناسه کسب‌وکار (برای امنیت)
		hard_delete: حذف کامل یا soft delete
	"""
	repo = ProjectRepository(db)
	project = repo.get_by_id(project_id)
	
	if not project:
		raise ApiError("PROJECT_NOT_FOUND", "پروژه یافت نشد", http_status=404)
	
	# بررسی دسترسی
	if project.business_id != business_id:
		raise ApiError("ACCESS_DENIED", "دسترسی به این پروژه ندارید", http_status=403)
	
	# بررسی وجود اسناد مرتبط
	document_count = db.query(func.count(Document.id)).filter(
		Document.project_id == project_id
	).scalar()
	
	if document_count > 0 and hard_delete:
		raise ApiError(
			"PROJECT_HAS_DOCUMENTS",
			f"این پروژه دارای {document_count} سند است و نمی‌توان آن را حذف کرد",
			http_status=400
		)
	
	if hard_delete:
		repo.hard_delete(project)
	else:
		repo.delete(project)
	
	db.commit()
	
	logger.info(f"Project {'hard ' if hard_delete else ''}deleted: {project_id}")


def get_project_statistics(db: Session, project_id: int) -> Dict[str, Any]:
	"""
	دریافت آمار مالی پروژه
	
	Args:
		db: نشست پایگاه داده
		project_id: شناسه پروژه
	
	Returns:
		دیکشنری حاوی آمار
	"""
	# تعداد اسناد
	total_documents = db.query(func.count(Document.id)).filter(
		Document.project_id == project_id
	).scalar() or 0
	
	# تعداد اسناد به تفکیک نوع
	document_types = db.query(
		Document.document_type,
		func.count(Document.id).label('count')
	).filter(
		Document.project_id == project_id
	).group_by(Document.document_type).all()
	
	documents_by_type = {dt: count for dt, count in document_types}
	
	# مجموع بدهکار و بستانکار
	totals = db.query(
		func.sum(DocumentLine.debit).label('total_debit'),
		func.sum(DocumentLine.credit).label('total_credit')
	).join(Document).filter(
		Document.project_id == project_id
	).first()
	
	total_debit = float(totals.total_debit or 0)
	total_credit = float(totals.total_credit or 0)
	
	return {
		'total_documents': total_documents,
		'documents_by_type': documents_by_type,
		'total_debit': total_debit,
		'total_credit': total_credit,
		'balance': total_debit - total_credit
	}


def list_project_documents(
	db: Session,
	project_id: int,
	skip: int = 0,
	limit: int = 50
) -> Tuple[List[Document], int]:
	"""
	لیست اسناد یک پروژه
	
	Args:
		db: نشست پایگاه داده
		project_id: شناسه پروژه
		skip: تعداد رکورد صرف‌نظر شده
		limit: حداکثر تعداد رکورد
	
	Returns:
		لیست اسناد و تعداد کل
	"""
	query = db.query(Document).filter(Document.project_id == project_id)
	
	total = query.count()
	documents = query.order_by(Document.document_date.desc()).offset(skip).limit(limit).all()
	
	return documents, total




def _require_project_in_business(db: Session, business_id: int, project_id: int) -> Project:
    project = db.query(Project).filter(
        Project.id == project_id,
        Project.business_id == business_id,
    ).first()
    if not project:
        raise ApiError("PROJECT_NOT_FOUND", "پروژه یافت نشد", http_status=404)
    return project


def _business_member_user(db: Session, business: Business, user_id: int) -> User:
    user = db.get(User, int(user_id))
    if not user:
        raise ApiError("PROJECT_MEMBER_USER_NOT_FOUND", "کاربر یافت نشد", http_status=404)
    if int(user.id) == int(business.owner_id):
        return user
    permission = db.query(BusinessPermission).filter(
        BusinessPermission.business_id == business.id,
        BusinessPermission.user_id == user.id,
    ).first()
    if not permission or not membership_is_active(permission):
        raise ApiError(
            "PROJECT_MEMBER_NOT_BUSINESS_MEMBER",
            "کاربر عضو فعال این کسب‌وکار نیست",
            http_status=400,
        )
    return user


def list_project_members(db: Session, business_id: int, project_id: int) -> list[ProjectMember]:
    _require_project_in_business(db, business_id, project_id)
    return (
        db.query(ProjectMember)
        .filter(
            ProjectMember.business_id == business_id,
            ProjectMember.project_id == project_id,
        )
        .order_by(ProjectMember.created_at.asc(), ProjectMember.id.asc())
        .all()
    )



def _can_manage_project_members(
    db: Session,
    business: Business,
    project: Project,
    actor_user_id: int,
) -> bool:
    if int(business.owner_id) == int(actor_user_id):
        return True
    if project.manager_user_id and int(project.manager_user_id) == int(actor_user_id):
        return True
    member = db.query(ProjectMember).filter(
        ProjectMember.business_id == business.id,
        ProjectMember.project_id == project.id,
        ProjectMember.user_id == actor_user_id,
        ProjectMember.role.in_(["owner", "manager"]),
    ).first()
    return member is not None


def upsert_project_member(
    db: Session,
    business_id: int,
    project_id: int,
    actor_user_id: int,
    user_id: int,
    role: str = "member",
) -> ProjectMember:
    project = _require_project_in_business(db, business_id, project_id)
    business = db.get(Business, business_id)
    if not business:
        raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)
    if not _can_manage_project_members(db, business, project, actor_user_id):
        raise ApiError(
            "PROJECT_MEMBER_MANAGE_FORBIDDEN",
            "فقط مالک کسب‌وکار یا مدیر پروژه می‌تواند اعضا را تغییر دهد",
            http_status=403,
        )
    user = _business_member_user(db, business, user_id)
    member = db.query(ProjectMember).filter(
        ProjectMember.business_id == business_id,
        ProjectMember.project_id == project_id,
        ProjectMember.user_id == user.id,
    ).first()
    if member:
        member.role = role
        db.commit()
        db.refresh(member)
        return member
    member = ProjectMember(
        business_id=business_id,
        project_id=project.id,
        user_id=user.id,
        role=role,
        added_by_user_id=actor_user_id,
    )
    db.add(member)
    db.commit()
    db.refresh(member)
    return member


def remove_project_member(
    db: Session,
    business_id: int,
    project_id: int,
    actor_user_id: int,
    user_id: int,
) -> None:
    project = _require_project_in_business(db, business_id, project_id)
    business = db.get(Business, business_id)
    if not business:
        raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)
    if not _can_manage_project_members(db, business, project, actor_user_id):
        raise ApiError(
            "PROJECT_MEMBER_MANAGE_FORBIDDEN",
            "فقط مالک کسب‌وکار یا مدیر پروژه می‌تواند اعضا را تغییر دهد",
            http_status=403,
        )
    if project.manager_user_id == user_id:
        raise ApiError(
            "PROJECT_MEMBER_IS_MANAGER",
            "ابتدا مدیر پروژه را تغییر دهید",
            http_status=400,
        )
    member = db.query(ProjectMember).filter(
        ProjectMember.business_id == business_id,
        ProjectMember.project_id == project_id,
        ProjectMember.user_id == user_id,
    ).first()
    if not member:
        raise ApiError("PROJECT_MEMBER_NOT_FOUND", "عضو پروژه یافت نشد", http_status=404)
    db.delete(member)
    db.commit()


def get_project_workspace(db: Session, business_id: int, project_id: int) -> Dict[str, Any]:
    project = _require_project_in_business(db, business_id, project_id)
    task_base = db.query(Task).filter(
        Task.business_id == business_id,
        Task.project_id == project_id,
        Task.deleted_at.is_(None),
    )
    total_tasks = task_base.count()
    completed_tasks = task_base.filter(Task.completed_at.is_not(None)).count()
    open_tasks = max(total_tasks - completed_tasks, 0)
    now = datetime.now(timezone.utc)
    overdue_tasks = task_base.filter(
        Task.completed_at.is_(None),
        Task.due_at.is_not(None),
        Task.due_at < now,
    ).count()
    status_rows = (
        db.query(
            TaskStatus.id,
            TaskStatus.key,
            TaskStatus.name,
            TaskStatus.category,
            TaskStatus.color,
            func.count(Task.id),
        )
        .outerjoin(
            Task,
            and_(
                Task.status_id == TaskStatus.id,
                Task.business_id == business_id,
                Task.project_id == project_id,
                Task.deleted_at.is_(None),
            ),
        )
        .filter(TaskStatus.business_id == business_id)
        .group_by(
            TaskStatus.id,
            TaskStatus.key,
            TaskStatus.name,
            TaskStatus.category,
            TaskStatus.color,
            TaskStatus.sort_order,
        )
        .order_by(TaskStatus.sort_order.asc())
        .all()
    )
    return {
        "project": project,
        "task_statistics": {
            "total": total_tasks,
            "open": open_tasks,
            "completed": completed_tasks,
            "overdue": overdue_tasks,
            "progress_percent": round((completed_tasks / total_tasks) * 100, 1)
            if total_tasks else 0.0,
            "by_status": [
                {
                    "id": row[0], "key": row[1], "name": row[2],
                    "category": row[3], "color": row[4], "count": int(row[5] or 0),
                }
                for row in status_rows
            ],
        },
        "financial_statistics": get_project_statistics(db, project_id),
        "members": list_project_members(db, business_id, project_id),
    }
