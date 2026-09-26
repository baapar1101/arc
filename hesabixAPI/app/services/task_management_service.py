"""
Core task engine.

Phase 1 implements task CRUD, completion/reopen, assignment, status,
priority, due date and project linkage on the Phase 0 domain model.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Iterable, Optional

from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.business_permission import BusinessPermission
from adapters.db.models.project import Project
from adapters.db.models.task_management import (
    Task,
    ProjectMember,
    TaskActivity,
    TaskAssignee,
    TaskStatus,
)
from adapters.db.models.user import User
from adapters.db.repositories.task_repository import TaskRepository
from app.core.business_membership import membership_is_active
from app.core.responses import ApiError


_DEFAULT_STATUSES = (
    ("backlog", "Backlog", "backlog", "#64748B", 1000, False, False),
    ("todo", "To Do", "unstarted", "#3B82F6", 2000, True, False),
    ("in_progress", "In Progress", "started", "#F59E0B", 3000, False, False),
    ("done", "Done", "completed", "#22C55E", 4000, False, True),
    ("cancelled", "Cancelled", "cancelled", "#EF4444", 5000, False, True),
)

_ALLOWED_PRIORITIES = {"low", "normal", "high", "urgent"}


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _parse_datetime(value: Any) -> Optional[datetime]:
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        dt = value
    elif isinstance(value, str):
        try:
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError as exc:
            raise ApiError("TASK_INVALID_DATETIME", "Invalid date/time value", http_status=400) from exc
    else:
        raise ApiError("TASK_INVALID_DATETIME", "Invalid date/time value", http_status=400)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _validate_dates(start_at: Optional[datetime], due_at: Optional[datetime]) -> None:
    if start_at is not None and due_at is not None and due_at < start_at:
        raise ApiError(
            "TASK_INVALID_DATE_RANGE",
            "Task due date cannot be before its start date",
            http_status=400,
        )


def _require_business(db: Session, business_id: int) -> Business:
    business = db.get(Business, business_id)
    if not business or getattr(business, "deleted_at", None) is not None:
        raise ApiError("BUSINESS_NOT_FOUND", "Business not found", http_status=404)
    return business


def _require_project(db: Session, business_id: int, project_id: Optional[int]) -> Optional[Project]:
    if project_id is None:
        return None
    project = db.get(Project, int(project_id))
    if not project or int(project.business_id) != int(business_id):
        raise ApiError("TASK_PROJECT_NOT_FOUND", "Project not found in this business", http_status=404)
    return project


def _require_status(db: Session, business_id: int, status_id: Optional[int]) -> Optional[TaskStatus]:
    if status_id is None:
        return None
    status = db.get(TaskStatus, int(status_id))
    if not status or int(status.business_id) != int(business_id):
        raise ApiError("TASK_STATUS_NOT_FOUND", "Task status not found in this business", http_status=404)
    return status


def _require_business_member(db: Session, business: Business, user_id: int) -> User:
    user = db.get(User, int(user_id))
    if not user:
        raise ApiError("TASK_ASSIGNEE_NOT_FOUND", "Assignee user not found", http_status=404)

    if int(user.id) == int(business.owner_id):
        return user

    permission = (
        db.query(BusinessPermission)
        .filter(
            BusinessPermission.business_id == business.id,
            BusinessPermission.user_id == user.id,
        )
        .first()
    )
    if not permission or not membership_is_active(permission):
        raise ApiError(
            "TASK_ASSIGNEE_NOT_MEMBER",
            "Assignee is not an active member of this business",
            http_status=400,
        )
    return user


def ensure_default_task_statuses(db: Session, business_id: int) -> list[TaskStatus]:
    _require_business(db, business_id)
    existing = (
        db.query(TaskStatus)
        .filter(TaskStatus.business_id == business_id)
        .order_by(TaskStatus.sort_order.asc(), TaskStatus.id.asc())
        .all()
    )
    by_key = {item.key: item for item in existing}
    has_default = any(item.is_default for item in existing)
    created = False

    for key, name, category, color, sort_order, is_default, is_closed in _DEFAULT_STATUSES:
        if key in by_key:
            continue
        row = TaskStatus(
            business_id=business_id,
            key=key,
            name=name,
            category=category,
            color=color,
            sort_order=sort_order,
            is_default=is_default and not has_default,
            is_closed=is_closed,
        )
        if row.is_default:
            has_default = True
        db.add(row)
        created = True

    if created:
        db.commit()

    return (
        db.query(TaskStatus)
        .filter(TaskStatus.business_id == business_id)
        .order_by(TaskStatus.sort_order.asc(), TaskStatus.id.asc())
        .all()
    )


def _default_status(db: Session, business_id: int) -> TaskStatus:
    statuses = ensure_default_task_statuses(db, business_id)
    for item in statuses:
        if item.is_default:
            return item
    for item in statuses:
        if item.key == "todo":
            return item
    if not statuses:
        raise ApiError("TASK_STATUS_MISSING", "No task status is available", http_status=500)
    return statuses[0]


def _status_for_category(db: Session, business_id: int, category: str) -> TaskStatus:
    statuses = ensure_default_task_statuses(db, business_id)
    for item in statuses:
        if item.category == category:
            return item
    raise ApiError("TASK_STATUS_MISSING", f"No {category} task status is available", http_status=500)


def _record_activity(
    db: Session,
    *,
    task: Task,
    actor_user_id: Optional[int],
    event_type: str,
    event_data: Optional[dict[str, Any]] = None,
) -> None:
    db.add(
        TaskActivity(
            business_id=task.business_id,
            task_id=task.id,
            actor_user_id=actor_user_id,
            event_type=event_type,
            event_data=event_data or {},
        )
    )


def _normalize_assignee_ids(values: Optional[Iterable[int]]) -> list[int]:
    if values is None:
        return []
    result: list[int] = []
    seen: set[int] = set()
    for raw in values:
        value = int(raw)
        if value <= 0 or value in seen:
            continue
        seen.add(value)
        result.append(value)
    return result


def replace_task_assignees(
    db: Session,
    *,
    task: Task,
    assignee_user_ids: Iterable[int],
    actor_user_id: Optional[int],
    commit: bool = True,
) -> list[int]:
    business = _require_business(db, task.business_id)
    new_ids = _normalize_assignee_ids(assignee_user_ids)
    for user_id in new_ids:
        _require_business_member(db, business, user_id)

    current_rows = (
        db.query(TaskAssignee)
        .filter(
            TaskAssignee.business_id == task.business_id,
            TaskAssignee.task_id == task.id,
        )
        .all()
    )
    current_ids = [row.user_id for row in current_rows]
    if current_ids == new_ids:
        return current_ids

    db.query(TaskAssignee).filter(
        TaskAssignee.business_id == task.business_id,
        TaskAssignee.task_id == task.id,
    ).delete(synchronize_session=False)
    for user_id in new_ids:
        db.add(
            TaskAssignee(
                business_id=task.business_id,
                task_id=task.id,
                user_id=user_id,
                assigned_by_user_id=actor_user_id,
            )
        )
    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="assignees_changed",
        event_data={"from": current_ids, "to": new_ids},
    )
    if commit:
        db.commit()
    return new_ids


def create_task(
    db: Session,
    business_id: int,
    actor_user_id: int,
    data: dict[str, Any],
) -> Task:
    business = _require_business(db, business_id)
    title = str(data.get("title") or "").strip()
    if not title:
        raise ApiError("TASK_TITLE_REQUIRED", "Task title is required", http_status=400)

    project = _require_project(db, business_id, data.get("project_id"))
    status = _require_status(db, business_id, data.get("status_id")) or _default_status(db, business_id)

    priority = str(data.get("priority") or "normal")
    if priority not in _ALLOWED_PRIORITIES:
        raise ApiError("TASK_INVALID_PRIORITY", "Invalid task priority", http_status=400)

    start_at = _parse_datetime(data.get("start_at"))
    due_at = _parse_datetime(data.get("due_at"))
    _validate_dates(start_at, due_at)

    repo = TaskRepository(db)
    task = Task(
        business_id=business_id,
        project_id=project.id if project else None,
        status_id=status.id,
        title=title,
        description=data.get("description"),
        priority=priority,
        sort_order=repo.next_sort_order(business_id, project.id if project else None),
        start_at=start_at,
        due_at=due_at,
        estimated_minutes=data.get("estimated_minutes"),
        created_by_user_id=actor_user_id,
    )
    db.add(task)
    db.flush()

    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="task_created",
        event_data={"status_id": status.id, "project_id": task.project_id},
    )

    assignee_ids = _normalize_assignee_ids(data.get("assignee_user_ids"))
    for user_id in assignee_ids:
        _require_business_member(db, business, user_id)
        db.add(
            TaskAssignee(
                business_id=task.business_id,
                task_id=task.id,
                user_id=user_id,
                assigned_by_user_id=actor_user_id,
            )
        )

    db.commit()
    return repo.get_by_id(task.id, business_id) or task


def update_task(
    db: Session,
    business_id: int,
    task_id: int,
    actor_user_id: int,
    data: dict[str, Any],
) -> Task:
    repo = TaskRepository(db)
    task = repo.get_by_id(task_id, business_id)
    if not task:
        raise ApiError("TASK_NOT_FOUND", "Task not found", http_status=404)

    changes: dict[str, Any] = {}

    if "title" in data:
        title = str(data.get("title") or "").strip()
        if not title:
            raise ApiError("TASK_TITLE_REQUIRED", "Task title is required", http_status=400)
        if title != task.title:
            changes["title"] = {"from": task.title, "to": title}
            task.title = title

    if "description" in data:
        task.description = data.get("description")

    if "project_id" in data:
        project = _require_project(db, business_id, data.get("project_id"))
        new_project_id = project.id if project else None
        if new_project_id != task.project_id:
            changes["project_id"] = {"from": task.project_id, "to": new_project_id}
            task.project_id = new_project_id

    if "status_id" in data:
        status = _require_status(db, business_id, data.get("status_id")) or _default_status(db, business_id)
        if status.id != task.status_id:
            changes["status_id"] = {"from": task.status_id, "to": status.id}
            task.status_id = status.id
        if status.category == "completed":
            task.completed_at = task.completed_at or _now()
        else:
            task.completed_at = None

    if "priority" in data:
        priority = str(data.get("priority") or "normal")
        if priority not in _ALLOWED_PRIORITIES:
            raise ApiError("TASK_INVALID_PRIORITY", "Invalid task priority", http_status=400)
        if priority != task.priority:
            changes["priority"] = {"from": task.priority, "to": priority}
            task.priority = priority

    next_start_at = _parse_datetime(data.get("start_at")) if "start_at" in data else task.start_at
    next_due_at = _parse_datetime(data.get("due_at")) if "due_at" in data else task.due_at
    _validate_dates(next_start_at, next_due_at)
    if "start_at" in data:
        task.start_at = next_start_at
    if "due_at" in data:
        task.due_at = next_due_at
    if "estimated_minutes" in data:
        value = data.get("estimated_minutes")
        if value is not None and int(value) < 0:
            raise ApiError("TASK_INVALID_ESTIMATE", "Estimated minutes cannot be negative", http_status=400)
        task.estimated_minutes = int(value) if value is not None else None

    task.updated_at = _now()

    if changes:
        _record_activity(
            db,
            task=task,
            actor_user_id=actor_user_id,
            event_type="task_updated",
            event_data=changes,
        )

    if "assignee_user_ids" in data:
        replace_task_assignees(
            db,
            task=task,
            assignee_user_ids=data.get("assignee_user_ids") or [],
            actor_user_id=actor_user_id,
            commit=False,
        )

    db.commit()
    return repo.get_by_id(task.id, business_id) or task


def complete_task(db: Session, business_id: int, task_id: int, actor_user_id: int) -> Task:
    repo = TaskRepository(db)
    task = repo.get_by_id(task_id, business_id)
    if not task:
        raise ApiError("TASK_NOT_FOUND", "Task not found", http_status=404)

    done = _status_for_category(db, business_id, "completed")
    previous_status_id = task.status_id
    task.status_id = done.id
    task.completed_at = _now()
    task.updated_at = _now()
    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="task_completed",
        event_data={"from_status_id": previous_status_id, "to_status_id": done.id},
    )
    db.commit()
    return repo.get_by_id(task.id, business_id) or task


def reopen_task(db: Session, business_id: int, task_id: int, actor_user_id: int) -> Task:
    repo = TaskRepository(db)
    task = repo.get_by_id(task_id, business_id)
    if not task:
        raise ApiError("TASK_NOT_FOUND", "Task not found", http_status=404)

    todo = _default_status(db, business_id)
    previous_status_id = task.status_id
    task.status_id = todo.id
    task.completed_at = None
    task.updated_at = _now()
    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="task_reopened",
        event_data={"from_status_id": previous_status_id, "to_status_id": todo.id},
    )
    db.commit()
    return repo.get_by_id(task.id, business_id) or task


def soft_delete_task(db: Session, business_id: int, task_id: int, actor_user_id: int) -> None:
    repo = TaskRepository(db)
    task = repo.get_by_id(task_id, business_id)
    if not task:
        raise ApiError("TASK_NOT_FOUND", "Task not found", http_status=404)
    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="task_deleted",
        event_data={},
    )
    task.deleted_at = _now()
    task.updated_at = _now()
    db.commit()


def list_available_assignees(db: Session, business_id: int) -> list[dict[str, Any]]:
    business = _require_business(db, business_id)
    permission_rows = (
        db.query(BusinessPermission)
        .filter(BusinessPermission.business_id == business_id)
        .all()
    )

    user_ids: list[int] = [int(business.owner_id)]
    for permission in permission_rows:
        if not membership_is_active(permission):
            continue
        if permission.user_id not in user_ids:
            user_ids.append(int(permission.user_id))

    users = db.query(User).filter(User.id.in_(user_ids)).all()
    by_id = {int(user.id): user for user in users}
    result: list[dict[str, Any]] = []
    for user_id in user_ids:
        user = by_id.get(user_id)
        if not user:
            continue
        name = f"{user.first_name or ''} {user.last_name or ''}".strip()
        result.append(
            {
                "user_id": user.id,
                "name": name or user.email or user.mobile or f"User {user.id}",
                "email": user.email,
                "mobile": user.mobile,
                "role": "owner" if int(user.id) == int(business.owner_id) else "member",
            }
        )
    return result



def get_project_workspace_summary(
    db: Session,
    business_id: int,
    project_id: int,
) -> dict[str, Any]:
    """Plane-inspired project workspace summary over the native Project entity."""
    project = _require_project(db, business_id, project_id)
    if project is None:
        raise ApiError("TASK_PROJECT_NOT_FOUND", "Project not found", http_status=404)

    ensure_default_task_statuses(db, business_id)

    base_filters = (
        Task.business_id == business_id,
        Task.project_id == project_id,
        Task.deleted_at.is_(None),
    )

    total = db.query(func.count(Task.id)).filter(*base_filters).scalar() or 0
    completed = (
        db.query(func.count(Task.id))
        .filter(*base_filters, Task.completed_at.is_not(None))
        .scalar()
        or 0
    )
    cancelled = (
        db.query(func.count(Task.id))
        .join(TaskStatus, Task.status_id == TaskStatus.id)
        .filter(*base_filters, TaskStatus.category == "cancelled")
        .scalar()
        or 0
    )
    overdue = (
        db.query(func.count(Task.id))
        .outerjoin(TaskStatus, Task.status_id == TaskStatus.id)
        .filter(
            *base_filters,
            Task.completed_at.is_(None),
            Task.due_at.is_not(None),
            Task.due_at < _now(),
            or_(TaskStatus.category.is_(None), TaskStatus.category != "cancelled"),
        )
        .scalar()
        or 0
    )
    open_count = max(int(total) - int(completed) - int(cancelled), 0)

    project_members = (
        db.query(func.count(ProjectMember.id))
        .filter(
            ProjectMember.business_id == business_id,
            ProjectMember.project_id == project_id,
        )
        .scalar()
        or 0
    )
    active_assignees = (
        db.query(func.count(func.distinct(TaskAssignee.user_id)))
        .join(Task, TaskAssignee.task_id == Task.id)
        .filter(
            TaskAssignee.business_id == business_id,
            Task.project_id == project_id,
            Task.deleted_at.is_(None),
        )
        .scalar()
        or 0
    )

    progress_percent = (
        round((int(completed) / int(total)) * 100, 1) if int(total) > 0 else 0.0
    )
    status_names = {
        "active": "فعال",
        "completed": "تکمیل شده",
        "on_hold": "معلق",
        "cancelled": "لغو شده",
    }

    manager_name = None
    if project.manager:
        manager_name = (
            f"{project.manager.first_name or ''} {project.manager.last_name or ''}".strip()
            or project.manager.email
        )

    return {
        "project": {
            "id": project.id,
            "business_id": project.business_id,
            "code": project.code,
            "name": project.name,
            "description": project.description,
            "status": project.status,
            "status_name": status_names.get(project.status, project.status),
            "start_date": project.start_date,
            "end_date": project.end_date,
            "budget": float(project.budget) if project.budget is not None else None,
            "currency_id": project.currency_id,
            "manager_user_id": project.manager_user_id,
            "manager_name": manager_name,
            "person_id": project.person_id,
            "person_name": project.person.alias_name if project.person else None,
            "is_active": project.is_active,
            "created_at": project.created_at,
            "updated_at": project.updated_at,
        },
        "tasks": {
            "total": int(total),
            "open": int(open_count),
            "completed": int(completed),
            "cancelled": int(cancelled),
            "overdue": int(overdue),
            "progress_percent": progress_percent,
        },
        "team": {
            "project_members": int(project_members),
            "active_task_assignees": int(active_assignees),
        },
    }
