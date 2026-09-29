"""
سرویس مدیریت پروژه‌ها
"""

from __future__ import annotations

from typing import Dict, Any, List, Optional, Tuple
from datetime import datetime, date, timezone
from decimal import Decimal
import logging

from sqlalchemy.orm import Session
from sqlalchemy import and_, func, select

from adapters.db.models.project import Project
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.business import Business
from adapters.db.models.currency import Currency
from adapters.db.models.user import User
from adapters.db.models.person import Person
from adapters.db.models.business_permission import BusinessPermission
from adapters.db.models.task_management import Milestone, ProjectCycle, ProjectCycleTask, ProjectMember, Task, TaskActivity, TaskAttachment, TaskRelation, TaskStatus
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
    from app.services.task_notification_service import notify_project_member_added
    notify_project_member_added(
        db,
        business_id=business_id,
        project_id=project.id,
        project_name=project.name,
        user_id=user.id,
        actor_user_id=actor_user_id,
    )
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



def list_project_activity(
    db: Session,
    business_id: int,
    project_id: int,
    limit: int = 200,
) -> list[dict[str, Any]]:
    """Recent immutable task-domain activity for a project workspace."""
    _require_project_in_business(db, business_id, project_id)
    rows = (
        db.query(TaskActivity, Task.title)
        .join(Task, TaskActivity.task_id == Task.id)
        .filter(
            TaskActivity.business_id == business_id,
            Task.business_id == business_id,
            Task.project_id == project_id,
            Task.deleted_at.is_(None),
        )
        .order_by(TaskActivity.created_at.desc(), TaskActivity.id.desc())
        .limit(max(1, min(int(limit), 500)))
        .all()
    )
    return [
        {"activity": activity, "task_title": task_title}
        for activity, task_title in rows
    ]


def list_project_files(
    db: Session,
    business_id: int,
    project_id: int,
    limit: int = 200,
) -> list[dict[str, Any]]:
    """Task attachments surfaced together in the project workspace."""
    _require_project_in_business(db, business_id, project_id)
    rows = (
        db.query(TaskAttachment, Task.title)
        .join(Task, TaskAttachment.task_id == Task.id)
        .filter(
            TaskAttachment.business_id == business_id,
            Task.business_id == business_id,
            Task.project_id == project_id,
            Task.deleted_at.is_(None),
        )
        .order_by(TaskAttachment.created_at.desc(), TaskAttachment.id.desc())
        .limit(max(1, min(int(limit), 500)))
        .all()
    )
    return [
        {"attachment": attachment, "task_title": task_title}
        for attachment, task_title in rows
    ]


def get_project_timeline(
    db: Session,
    business_id: int,
    project_id: int,
) -> Dict[str, Any]:
    """Timeline/Gantt support payload for a project.

    Full task details stay on the normal task list endpoint; this endpoint
    supplies scheduled IDs/date bounds and dependency edges only.
    """
    _require_project_in_business(db, business_id, project_id)

    scheduled = (
        db.query(Task.id, Task.start_at, Task.due_at)
        .filter(
            Task.business_id == business_id,
            Task.project_id == project_id,
            Task.deleted_at.is_(None),
            ((Task.start_at.is_not(None)) | (Task.due_at.is_not(None))),
        )
        .order_by(Task.sort_order.asc(), Task.id.asc())
        .all()
    )
    task_ids = [int(row[0]) for row in scheduled]
    task_id_set = set(task_ids)

    dependencies = []
    if task_ids:
        relation_rows = (
            db.query(TaskRelation)
            .filter(
                TaskRelation.business_id == business_id,
                TaskRelation.relation_type == "blocks",
                TaskRelation.task_id.in_(task_ids),
                TaskRelation.related_task_id.in_(task_ids),
            )
            .order_by(TaskRelation.id.asc())
            .all()
        )
        dependencies = [
            {
                "id": relation.id,
                "from_task_id": relation.task_id,
                "to_task_id": relation.related_task_id,
            }
            for relation in relation_rows
            if relation.task_id in task_id_set
            and relation.related_task_id in task_id_set
        ]

    starts = []
    ends = []
    items = []
    for task_id, start_at, due_at in scheduled:
        start = start_at or due_at
        end = due_at or start_at
        if start is None or end is None:
            continue
        starts.append(start)
        ends.append(end)
        items.append(
            {
                "task_id": int(task_id),
                "start_at": start_at,
                "due_at": due_at,
            }
        )

    return {
        "items": items,
        "dependencies": dependencies,
        "range": {
            "start_at": min(starts) if starts else None,
            "end_at": max(ends) if ends else None,
        },
    }



_MILESTONE_STATUSES = {"open", "completed", "cancelled"}


def _parse_milestone_datetime(value: Any) -> Optional[datetime]:
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        dt = value
    elif isinstance(value, str):
        try:
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError as exc:
            raise ApiError(
                "PROJECT_MILESTONE_INVALID_DATETIME",
                "Invalid milestone date/time",
                http_status=400,
            ) from exc
    else:
        raise ApiError(
            "PROJECT_MILESTONE_INVALID_DATETIME",
            "Invalid milestone date/time",
            http_status=400,
        )
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _validate_milestone_dates(
    start_at: Optional[datetime],
    target_at: Optional[datetime],
) -> None:
    if start_at is not None and target_at is not None and target_at < start_at:
        raise ApiError(
            "PROJECT_MILESTONE_INVALID_DATE_RANGE",
            "Milestone target cannot be before its start",
            http_status=400,
        )


def list_project_milestones(
    db: Session,
    business_id: int,
    project_id: int,
) -> list[Dict[str, Any]]:
    _require_project_in_business(db, business_id, project_id)
    milestones = (
        db.query(Milestone)
        .filter(
            Milestone.business_id == business_id,
            Milestone.project_id == project_id,
        )
        .order_by(
            Milestone.sort_order.asc(),
            Milestone.target_at.asc().nullslast(),
            Milestone.id.asc(),
        )
        .all()
    )
    result: list[Dict[str, Any]] = []
    for milestone in milestones:
        task_query = db.query(Task).filter(
            Task.business_id == business_id,
            Task.project_id == project_id,
            Task.milestone_id == milestone.id,
            Task.deleted_at.is_(None),
        )
        total = task_query.count()
        completed = task_query.filter(Task.completed_at.is_not(None)).count()
        result.append(
            {
                "milestone": milestone,
                "task_total": int(total),
                "task_completed": int(completed),
                "progress_percent": round((completed / total) * 100, 1) if total else 0.0,
            }
        )
    return result


def create_project_milestone(
    db: Session,
    business_id: int,
    project_id: int,
    actor_user_id: int,
    data: Dict[str, Any],
) -> Milestone:
    _require_project_in_business(db, business_id, project_id)
    business = db.get(Business, business_id)
    if not business:
        raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)
    owner_id = data.get("owner_id")
    if owner_id is not None:
        _business_member_user(db, business, int(owner_id))
    title = str(data.get("title") or "").strip()
    if not title:
        raise ApiError(
            "PROJECT_MILESTONE_TITLE_REQUIRED",
            "Milestone title is required",
            http_status=400,
        )
    status = str(data.get("status") or "open").strip().lower()
    if status not in _MILESTONE_STATUSES:
        raise ApiError(
            "PROJECT_MILESTONE_INVALID_STATUS",
            "Invalid milestone status",
            http_status=400,
        )
    start_at = _parse_milestone_datetime(data.get("start_at"))
    target_at = _parse_milestone_datetime(data.get("target_at"))
    _validate_milestone_dates(start_at, target_at)
    milestone = Milestone(
        business_id=business_id,
        project_id=project_id,
        title=title,
        description=data.get("description"),
        start_at=start_at,
        target_at=target_at,
        owner_id=int(owner_id) if owner_id is not None else None,
        status=status,
        sort_order=Decimal(str(data.get("sort_order") or 0)),
        created_by_user_id=actor_user_id,
    )
    db.add(milestone)
    db.commit()
    db.refresh(milestone)
    return milestone


def update_project_milestone(
    db: Session,
    business_id: int,
    project_id: int,
    milestone_id: int,
    data: Dict[str, Any],
) -> Milestone:
    _require_project_in_business(db, business_id, project_id)
    business = db.get(Business, business_id)
    if not business:
        raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)
    milestone = (
        db.query(Milestone)
        .filter(
            Milestone.id == milestone_id,
            Milestone.business_id == business_id,
            Milestone.project_id == project_id,
        )
        .first()
    )
    if not milestone:
        raise ApiError(
            "PROJECT_MILESTONE_NOT_FOUND",
            "Milestone not found",
            http_status=404,
        )

    if "title" in data:
        title = str(data.get("title") or "").strip()
        if not title:
            raise ApiError(
                "PROJECT_MILESTONE_TITLE_REQUIRED",
                "Milestone title is required",
                http_status=400,
            )
        milestone.title = title
    if "description" in data:
        milestone.description = data.get("description")
    if "owner_id" in data:
        owner_id = data.get("owner_id")
        if owner_id is not None:
            _business_member_user(db, business, int(owner_id))
            milestone.owner_id = int(owner_id)
        else:
            milestone.owner_id = None
    if "status" in data:
        status = str(data.get("status") or "open").strip().lower()
        if status not in _MILESTONE_STATUSES:
            raise ApiError(
                "PROJECT_MILESTONE_INVALID_STATUS",
                "Invalid milestone status",
                http_status=400,
            )
        milestone.status = status
    if "sort_order" in data:
        milestone.sort_order = Decimal(str(data.get("sort_order") or 0))

    start_at = (
        _parse_milestone_datetime(data.get("start_at"))
        if "start_at" in data
        else milestone.start_at
    )
    target_at = (
        _parse_milestone_datetime(data.get("target_at"))
        if "target_at" in data
        else milestone.target_at
    )
    _validate_milestone_dates(start_at, target_at)
    milestone.start_at = start_at
    milestone.target_at = target_at
    milestone.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(milestone)
    return milestone


def delete_project_milestone(
    db: Session,
    business_id: int,
    project_id: int,
    milestone_id: int,
) -> None:
    _require_project_in_business(db, business_id, project_id)
    milestone = (
        db.query(Milestone)
        .filter(
            Milestone.id == milestone_id,
            Milestone.business_id == business_id,
            Milestone.project_id == project_id,
        )
        .first()
    )
    if not milestone:
        raise ApiError(
            "PROJECT_MILESTONE_NOT_FOUND",
            "Milestone not found",
            http_status=404,
        )
    db.delete(milestone)
    db.commit()



_CYCLE_STATUSES = {"planned", "active", "completed", "cancelled"}


def _parse_cycle_datetime(value: Any) -> Optional[datetime]:
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        dt = value
    elif isinstance(value, str):
        try:
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError as exc:
            raise ApiError(
                "PROJECT_CYCLE_INVALID_DATETIME",
                "Invalid cycle date/time",
                http_status=400,
            ) from exc
    else:
        raise ApiError(
            "PROJECT_CYCLE_INVALID_DATETIME",
            "Invalid cycle date/time",
            http_status=400,
        )
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _validate_cycle_dates(
    start_at: Optional[datetime],
    end_at: Optional[datetime],
) -> None:
    if start_at is not None and end_at is not None and end_at < start_at:
        raise ApiError(
            "PROJECT_CYCLE_INVALID_DATE_RANGE",
            "Cycle end cannot be before its start",
            http_status=400,
        )


def list_project_cycles(
    db: Session,
    business_id: int,
    project_id: int,
) -> list[Dict[str, Any]]:
    _require_project_in_business(db, business_id, project_id)
    cycles = (
        db.query(ProjectCycle)
        .filter(
            ProjectCycle.business_id == business_id,
            ProjectCycle.project_id == project_id,
        )
        .order_by(
            ProjectCycle.start_at.desc().nullslast(),
            ProjectCycle.id.desc(),
        )
        .all()
    )
    result: list[Dict[str, Any]] = []
    for cycle in cycles:
        task_query = (
            db.query(Task)
            .join(
                ProjectCycleTask,
                ProjectCycleTask.task_id == Task.id,
            )
            .filter(
                ProjectCycleTask.business_id == business_id,
                ProjectCycleTask.cycle_id == cycle.id,
                Task.business_id == business_id,
                Task.project_id == project_id,
                Task.deleted_at.is_(None),
            )
        )
        task_rows = task_query.with_entities(Task.id, Task.completed_at).all()
        task_ids = [int(task_id) for task_id, _completed_at in task_rows]
        incomplete_task_ids = [
            int(task_id)
            for task_id, completed_at in task_rows
            if completed_at is None
        ]
        total = len(task_ids)
        completed = total - len(incomplete_task_ids)
        result.append(
            {
                "cycle": cycle,
                "task_total": int(total),
                "task_completed": int(completed),
                "progress_percent": round((completed / total) * 100, 1) if total else 0.0,
                "task_ids": task_ids,
                "incomplete_task_ids": incomplete_task_ids,
            }
        )
    return result


def list_project_cycle_backlog_task_ids(
    db: Session,
    business_id: int,
    project_id: int,
) -> list[int]:
    """Incomplete project tasks not scheduled into a planned/active cycle."""
    _require_project_in_business(db, business_id, project_id)
    scheduled_task_ids = (
        select(ProjectCycleTask.task_id)
        .join(ProjectCycle, ProjectCycle.id == ProjectCycleTask.cycle_id)
        .where(
            ProjectCycleTask.business_id == business_id,
            ProjectCycle.business_id == business_id,
            ProjectCycle.project_id == project_id,
            ProjectCycle.status.in_(["planned", "active"]),
        )
    )
    rows = (
        db.query(Task.id)
        .filter(
            Task.business_id == business_id,
            Task.project_id == project_id,
            Task.deleted_at.is_(None),
            Task.completed_at.is_(None),
            ~Task.id.in_(scheduled_task_ids),
        )
        .order_by(
            Task.due_at.asc().nullslast(),
            Task.sort_order.asc(),
            Task.id.asc(),
        )
        .all()
    )
    return [int(row[0]) for row in rows]


def add_task_to_project_cycle(
    db: Session,
    business_id: int,
    project_id: int,
    cycle_id: int,
    task_id: int,
) -> bool:
    _require_project_in_business(db, business_id, project_id)
    cycle = (
        db.query(ProjectCycle)
        .filter(
            ProjectCycle.id == cycle_id,
            ProjectCycle.business_id == business_id,
            ProjectCycle.project_id == project_id,
        )
        .first()
    )
    if not cycle:
        raise ApiError("PROJECT_CYCLE_NOT_FOUND", "Cycle not found", http_status=404)
    if cycle.status not in {"planned", "active"}:
        raise ApiError(
            "PROJECT_CYCLE_TASK_TARGET_INVALID",
            "Tasks can only be scheduled into planned or active cycles",
            http_status=400,
        )
    task = (
        db.query(Task)
        .filter(
            Task.id == task_id,
            Task.business_id == business_id,
            Task.project_id == project_id,
            Task.deleted_at.is_(None),
        )
        .first()
    )
    if not task:
        raise ApiError("TASK_NOT_FOUND", "Task not found in project", http_status=404)

    existing = (
        db.query(ProjectCycleTask)
        .filter(
            ProjectCycleTask.business_id == business_id,
            ProjectCycleTask.cycle_id == cycle_id,
            ProjectCycleTask.task_id == task_id,
        )
        .first()
    )
    if existing:
        return False
    db.add(
        ProjectCycleTask(
            business_id=business_id,
            cycle_id=cycle_id,
            task_id=task_id,
        )
    )
    db.commit()
    return True


def _carry_over_task_ids(
    source_rows: list[tuple[int, Optional[datetime]]],
    existing_target_ids: set[int],
) -> list[int]:
    return [
        int(task_id)
        for task_id, completed_at in source_rows
        if completed_at is None and int(task_id) not in existing_target_ids
    ]


def carry_over_project_cycle_tasks(
    db: Session,
    business_id: int,
    project_id: int,
    source_cycle_id: int,
    target_cycle_id: int,
) -> list[int]:
    _require_project_in_business(db, business_id, project_id)
    if source_cycle_id == target_cycle_id:
        raise ApiError(
            "PROJECT_CYCLE_CARRY_OVER_SAME_CYCLE",
            "Source and target cycles must be different",
            http_status=400,
        )

    cycles = (
        db.query(ProjectCycle)
        .filter(
            ProjectCycle.business_id == business_id,
            ProjectCycle.project_id == project_id,
            ProjectCycle.id.in_([source_cycle_id, target_cycle_id]),
        )
        .all()
    )
    by_id = {int(cycle.id): cycle for cycle in cycles}
    source = by_id.get(int(source_cycle_id))
    target = by_id.get(int(target_cycle_id))
    if source is None or target is None:
        raise ApiError(
            "PROJECT_CYCLE_NOT_FOUND",
            "Source or target cycle was not found",
            http_status=404,
        )
    if source.status not in {"active", "completed"}:
        raise ApiError(
            "PROJECT_CYCLE_CARRY_OVER_SOURCE_INVALID",
            "Carry-over source must be active or completed",
            http_status=400,
        )
    if target.status not in {"planned", "active"}:
        raise ApiError(
            "PROJECT_CYCLE_CARRY_OVER_TARGET_INVALID",
            "Carry-over target must be planned or active",
            http_status=400,
        )

    source_rows = (
        db.query(Task.id, Task.completed_at)
        .join(ProjectCycleTask, ProjectCycleTask.task_id == Task.id)
        .filter(
            ProjectCycleTask.business_id == business_id,
            ProjectCycleTask.cycle_id == source_cycle_id,
            Task.business_id == business_id,
            Task.project_id == project_id,
            Task.deleted_at.is_(None),
        )
        .all()
    )
    existing_target_ids = {
        int(row[0])
        for row in db.query(ProjectCycleTask.task_id)
        .filter(
            ProjectCycleTask.business_id == business_id,
            ProjectCycleTask.cycle_id == target_cycle_id,
        )
        .all()
    }
    task_ids = _carry_over_task_ids(source_rows, existing_target_ids)
    for task_id in task_ids:
        db.add(
            ProjectCycleTask(
                business_id=business_id,
                cycle_id=target_cycle_id,
                task_id=task_id,
            )
        )
    if task_ids:
        db.commit()
    return task_ids


def create_project_cycle(
    db: Session,
    business_id: int,
    project_id: int,
    actor_user_id: int,
    data: Dict[str, Any],
) -> ProjectCycle:
    _require_project_in_business(db, business_id, project_id)
    name = str(data.get("name") or "").strip()
    if not name:
        raise ApiError(
            "PROJECT_CYCLE_NAME_REQUIRED",
            "Cycle name is required",
            http_status=400,
        )
    status = str(data.get("status") or "planned").strip().lower()
    if status not in _CYCLE_STATUSES:
        raise ApiError(
            "PROJECT_CYCLE_INVALID_STATUS",
            "Invalid cycle status",
            http_status=400,
        )
    start_at = _parse_cycle_datetime(data.get("start_at"))
    end_at = _parse_cycle_datetime(data.get("end_at"))
    _validate_cycle_dates(start_at, end_at)
    cycle = ProjectCycle(
        business_id=business_id,
        project_id=project_id,
        name=name,
        goal=data.get("goal"),
        start_at=start_at,
        end_at=end_at,
        status=status,
        created_by_user_id=actor_user_id,
    )
    db.add(cycle)
    db.commit()
    db.refresh(cycle)
    return cycle


def update_project_cycle(
    db: Session,
    business_id: int,
    project_id: int,
    cycle_id: int,
    data: Dict[str, Any],
) -> ProjectCycle:
    _require_project_in_business(db, business_id, project_id)
    cycle = (
        db.query(ProjectCycle)
        .filter(
            ProjectCycle.id == cycle_id,
            ProjectCycle.business_id == business_id,
            ProjectCycle.project_id == project_id,
        )
        .first()
    )
    if not cycle:
        raise ApiError("PROJECT_CYCLE_NOT_FOUND", "Cycle not found", http_status=404)
    if "name" in data:
        name = str(data.get("name") or "").strip()
        if not name:
            raise ApiError(
                "PROJECT_CYCLE_NAME_REQUIRED",
                "Cycle name is required",
                http_status=400,
            )
        cycle.name = name
    if "goal" in data:
        cycle.goal = data.get("goal")
    if "status" in data:
        status = str(data.get("status") or "planned").strip().lower()
        if status not in _CYCLE_STATUSES:
            raise ApiError(
                "PROJECT_CYCLE_INVALID_STATUS",
                "Invalid cycle status",
                http_status=400,
            )
        cycle.status = status
    start_at = (
        _parse_cycle_datetime(data.get("start_at"))
        if "start_at" in data
        else cycle.start_at
    )
    end_at = (
        _parse_cycle_datetime(data.get("end_at"))
        if "end_at" in data
        else cycle.end_at
    )
    _validate_cycle_dates(start_at, end_at)
    cycle.start_at = start_at
    cycle.end_at = end_at
    cycle.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(cycle)
    return cycle


def delete_project_cycle(
    db: Session,
    business_id: int,
    project_id: int,
    cycle_id: int,
) -> None:
    _require_project_in_business(db, business_id, project_id)
    cycle = (
        db.query(ProjectCycle)
        .filter(
            ProjectCycle.id == cycle_id,
            ProjectCycle.business_id == business_id,
            ProjectCycle.project_id == project_id,
        )
        .first()
    )
    if not cycle:
        raise ApiError("PROJECT_CYCLE_NOT_FOUND", "Cycle not found", http_status=404)
    db.delete(cycle)
    db.commit()
