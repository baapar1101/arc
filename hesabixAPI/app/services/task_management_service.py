"""
Core task engine.

Phase 1 implements task CRUD, completion/reopen, assignment, status,
priority, due date and project linkage on the Phase 0 domain model.
"""

from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Iterable, Optional

from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.business_permission import BusinessPermission
from adapters.db.models.project import Project
from adapters.db.models.task_management import (
    Task,
    TaskActivity,
    TaskAssignee,
    TaskComment,
    TaskRelation,
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
_ALLOWED_RELATION_TYPES = {"blocks", "related", "duplicates"}


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


def _get_task_or_404(db: Session, business_id: int, task_id: int) -> Task:
    task = TaskRepository(db).get_by_id(task_id, business_id)
    if not task:
        raise ApiError("TASK_NOT_FOUND", "Task not found", http_status=404)
    return task


def _validate_parent_task(
    db: Session,
    business_id: int,
    *,
    task_id: Optional[int],
    parent_task_id: Optional[int],
    project_id: Optional[int],
) -> Optional[Task]:
    if parent_task_id is None:
        return None

    parent = _get_task_or_404(db, business_id, int(parent_task_id))
    if task_id is not None and int(parent.id) == int(task_id):
        raise ApiError(
            "TASK_PARENT_SELF",
            "A task cannot be its own parent",
            http_status=400,
        )
    if parent.project_id != project_id:
        raise ApiError(
            "TASK_PARENT_PROJECT_MISMATCH",
            "Parent and subtask must belong to the same project",
            http_status=400,
        )

    if task_id is not None:
        cursor = parent
        seen: set[int] = set()
        while cursor is not None:
            if cursor.id in seen:
                raise ApiError(
                    "TASK_PARENT_CYCLE",
                    "Existing task hierarchy contains a cycle",
                    http_status=409,
                )
            seen.add(cursor.id)
            if int(cursor.id) == int(task_id):
                raise ApiError(
                    "TASK_PARENT_CYCLE",
                    "Task hierarchy cannot contain a cycle",
                    http_status=400,
                )
            if cursor.parent_task_id is None:
                break
            cursor = TaskRepository(db).get_by_id(
                cursor.parent_task_id,
                business_id,
            )
    return parent


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

    requested_parent_id = data.get("parent_task_id")
    parent_task = None
    if requested_parent_id is not None:
        parent_task = _get_task_or_404(db, business_id, int(requested_parent_id))
        if data.get("project_id") is None:
            data["project_id"] = parent_task.project_id

    project = _require_project(db, business_id, data.get("project_id"))
    project_id = project.id if project else None
    parent_task = _validate_parent_task(
        db,
        business_id,
        task_id=None,
        parent_task_id=requested_parent_id,
        project_id=project_id,
    )
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
        project_id=project_id,
        parent_task_id=parent_task.id if parent_task else None,
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

    proposed_project_id = task.project_id
    if "project_id" in data:
        project = _require_project(db, business_id, data.get("project_id"))
        proposed_project_id = project.id if project else None

    proposed_parent_id = (
        data.get("parent_task_id")
        if "parent_task_id" in data
        else task.parent_task_id
    )
    _validate_parent_task(
        db,
        business_id,
        task_id=task.id,
        parent_task_id=proposed_parent_id,
        project_id=proposed_project_id,
    )

    if proposed_project_id != task.project_id:
        child_mismatch = (
            db.query(Task.id)
            .filter(
                Task.business_id == business_id,
                Task.parent_task_id == task.id,
                Task.deleted_at.is_(None),
                Task.project_id != proposed_project_id,
            )
            .first()
        )
        if child_mismatch:
            raise ApiError(
                "TASK_SUBTASK_PROJECT_MISMATCH",
                "Move subtasks before changing the parent project",
                http_status=400,
            )
        changes["project_id"] = {"from": task.project_id, "to": proposed_project_id}
        task.project_id = proposed_project_id

    if proposed_parent_id != task.parent_task_id:
        changes["parent_task_id"] = {
            "from": task.parent_task_id,
            "to": proposed_parent_id,
        }
        task.parent_task_id = proposed_parent_id

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



def move_task(
    db: Session,
    business_id: int,
    task_id: int,
    actor_user_id: int,
    target_status_id: int,
    target_index: int,
) -> Task:
    """Move/reorder a task inside a status column using stable fractional ordering."""
    repo = TaskRepository(db)
    task = repo.get_by_id(task_id, business_id)
    if not task:
        raise ApiError("TASK_NOT_FOUND", "Task not found", http_status=404)

    target_status = _require_status(db, business_id, target_status_id)
    if target_status is None:
        raise ApiError("TASK_STATUS_NOT_FOUND", "Task status not found", http_status=404)

    peer_query = db.query(Task).filter(
        Task.business_id == business_id,
        Task.deleted_at.is_(None),
        Task.status_id == target_status.id,
        Task.id != task.id,
    )
    if task.project_id is None:
        peer_query = peer_query.filter(Task.project_id.is_(None))
    else:
        peer_query = peer_query.filter(Task.project_id == task.project_id)

    peers = peer_query.order_by(Task.sort_order.asc(), Task.id.asc()).all()
    insert_at = max(0, min(int(target_index), len(peers)))

    def _renormalize() -> None:
        for index, peer in enumerate(peers, start=1):
            peer.sort_order = Decimal(index * 1000)
        db.flush()

    if not peers:
        next_order = Decimal(1000)
    elif insert_at == 0:
        first_order = Decimal(str(peers[0].sort_order or 0))
        next_order = first_order - Decimal(1000)
    elif insert_at >= len(peers):
        last_order = Decimal(str(peers[-1].sort_order or 0))
        next_order = last_order + Decimal(1000)
    else:
        before_order = Decimal(str(peers[insert_at - 1].sort_order or 0))
        after_order = Decimal(str(peers[insert_at].sort_order or 0))
        if after_order - before_order <= Decimal("0.000002"):
            _renormalize()
            before_order = Decimal(str(peers[insert_at - 1].sort_order or 0))
            after_order = Decimal(str(peers[insert_at].sort_order or 0))
        next_order = (before_order + after_order) / Decimal(2)

    previous_status_id = task.status_id
    previous_order = float(task.sort_order or 0)

    task.status_id = target_status.id
    task.sort_order = next_order
    task.completed_at = (
        task.completed_at or _now()
        if target_status.category == "completed"
        else None
    )
    task.updated_at = _now()

    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="task_moved",
        event_data={
            "from_status_id": previous_status_id,
            "to_status_id": target_status.id,
            "from_sort_order": previous_order,
            "to_sort_order": float(next_order),
            "target_index": insert_at,
        },
    )
    db.commit()
    return repo.get_by_id(task.id, business_id) or task



def create_subtask(
    db: Session,
    business_id: int,
    parent_task_id: int,
    actor_user_id: int,
    data: dict[str, Any],
) -> Task:
    parent = _get_task_or_404(db, business_id, parent_task_id)
    payload = dict(data)
    payload["parent_task_id"] = parent.id
    payload["project_id"] = parent.project_id
    task = create_task(db, business_id, actor_user_id, payload)
    _record_activity(
        db,
        task=parent,
        actor_user_id=actor_user_id,
        event_type="subtask_created",
        event_data={"subtask_id": task.id},
    )
    db.commit()
    return TaskRepository(db).get_by_id(task.id, business_id) or task


def get_task_structure(
    db: Session,
    business_id: int,
    task_id: int,
) -> dict[str, Any]:
    task = _get_task_or_404(db, business_id, task_id)
    parent = (
        TaskRepository(db).get_by_id(task.parent_task_id, business_id)
        if task.parent_task_id
        else None
    )
    subtasks = (
        db.query(Task)
        .filter(
            Task.business_id == business_id,
            Task.parent_task_id == task.id,
            Task.deleted_at.is_(None),
        )
        .order_by(Task.sort_order.asc(), Task.id.asc())
        .all()
    )
    relations = (
        db.query(TaskRelation)
        .filter(
            TaskRelation.business_id == business_id,
            (
                (TaskRelation.task_id == task.id)
                | (TaskRelation.related_task_id == task.id)
            ),
        )
        .order_by(TaskRelation.created_at.asc(), TaskRelation.id.asc())
        .all()
    )
    return {
        "task": task,
        "parent": parent,
        "subtasks": subtasks,
        "relations": relations,
    }


def _has_block_path(
    db: Session,
    business_id: int,
    start_task_id: int,
    target_task_id: int,
) -> bool:
    frontier = [int(start_task_id)]
    visited: set[int] = set()
    while frontier:
        current = frontier.pop()
        if current == int(target_task_id):
            return True
        if current in visited:
            continue
        visited.add(current)
        next_ids = [
            row[0]
            for row in (
                db.query(TaskRelation.related_task_id)
                .filter(
                    TaskRelation.business_id == business_id,
                    TaskRelation.task_id == current,
                    TaskRelation.relation_type == "blocks",
                )
                .all()
            )
        ]
        frontier.extend(int(value) for value in next_ids if value not in visited)
    return False


def add_task_relation(
    db: Session,
    business_id: int,
    task_id: int,
    actor_user_id: int,
    related_task_id: int,
    relation_type: str,
) -> TaskRelation:
    task = _get_task_or_404(db, business_id, task_id)
    related = _get_task_or_404(db, business_id, related_task_id)

    relation_type = str(relation_type or "").strip().lower()
    if relation_type not in _ALLOWED_RELATION_TYPES:
        raise ApiError(
            "TASK_RELATION_INVALID_TYPE",
            "Invalid task relation type",
            http_status=400,
        )
    if task.id == related.id:
        raise ApiError(
            "TASK_RELATION_SELF",
            "A task cannot be related to itself",
            http_status=400,
        )

    existing_query = db.query(TaskRelation).filter(
        TaskRelation.business_id == business_id,
        TaskRelation.relation_type == relation_type,
    )
    if relation_type in {"related", "duplicates"}:
        existing_query = existing_query.filter(
            (
                (TaskRelation.task_id == task.id)
                & (TaskRelation.related_task_id == related.id)
            )
            | (
                (TaskRelation.task_id == related.id)
                & (TaskRelation.related_task_id == task.id)
            )
        )
    else:
        existing_query = existing_query.filter(
            TaskRelation.task_id == task.id,
            TaskRelation.related_task_id == related.id,
        )
    if existing_query.first():
        raise ApiError(
            "TASK_RELATION_EXISTS",
            "Task relation already exists",
            http_status=409,
        )

    if relation_type == "blocks" and _has_block_path(
        db,
        business_id,
        related.id,
        task.id,
    ):
        raise ApiError(
            "TASK_RELATION_CYCLE",
            "Blocking relation would create a dependency cycle",
            http_status=400,
        )

    relation = TaskRelation(
        business_id=business_id,
        task_id=task.id,
        related_task_id=related.id,
        relation_type=relation_type,
        created_by_user_id=actor_user_id,
    )
    db.add(relation)
    db.flush()
    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="task_relation_added",
        event_data={
            "relation_id": relation.id,
            "relation_type": relation_type,
            "related_task_id": related.id,
        },
    )
    db.commit()
    db.refresh(relation)
    return relation


def delete_task_relation(
    db: Session,
    business_id: int,
    task_id: int,
    relation_id: int,
    actor_user_id: int,
) -> None:
    task = _get_task_or_404(db, business_id, task_id)
    relation = (
        db.query(TaskRelation)
        .filter(
            TaskRelation.id == relation_id,
            TaskRelation.business_id == business_id,
            (
                (TaskRelation.task_id == task.id)
                | (TaskRelation.related_task_id == task.id)
            ),
        )
        .first()
    )
    if not relation:
        raise ApiError(
            "TASK_RELATION_NOT_FOUND",
            "Task relation not found",
            http_status=404,
        )
    event_data = {
        "relation_id": relation.id,
        "relation_type": relation.relation_type,
        "task_id": relation.task_id,
        "related_task_id": relation.related_task_id,
    }
    db.delete(relation)
    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="task_relation_removed",
        event_data=event_data,
    )
    db.commit()



def list_task_comments(
    db: Session,
    business_id: int,
    task_id: int,
) -> list[TaskComment]:
    _get_task_or_404(db, business_id, task_id)
    return (
        db.query(TaskComment)
        .filter(
            TaskComment.business_id == business_id,
            TaskComment.task_id == task_id,
            TaskComment.deleted_at.is_(None),
        )
        .order_by(TaskComment.created_at.asc(), TaskComment.id.asc())
        .all()
    )


def add_task_comment(
    db: Session,
    business_id: int,
    task_id: int,
    actor_user_id: int,
    body: str,
) -> TaskComment:
    task = _get_task_or_404(db, business_id, task_id)
    clean_body = str(body or "").strip()
    if not clean_body:
        raise ApiError(
            "TASK_COMMENT_REQUIRED",
            "Comment body is required",
            http_status=400,
        )
    comment = TaskComment(
        business_id=business_id,
        task_id=task.id,
        author_user_id=actor_user_id,
        body=clean_body,
    )
    db.add(comment)
    db.flush()
    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="comment_added",
        event_data={"comment_id": comment.id},
    )
    db.commit()
    db.refresh(comment)
    return comment


def _require_comment_manager(
    db: Session,
    business_id: int,
    comment_id: int,
    actor_user_id: int,
) -> TaskComment:
    comment = (
        db.query(TaskComment)
        .filter(
            TaskComment.id == comment_id,
            TaskComment.business_id == business_id,
            TaskComment.deleted_at.is_(None),
        )
        .first()
    )
    if not comment:
        raise ApiError(
            "TASK_COMMENT_NOT_FOUND",
            "Comment not found",
            http_status=404,
        )
    business = _require_business(db, business_id)
    if (
        comment.author_user_id != actor_user_id
        and int(business.owner_id) != int(actor_user_id)
    ):
        raise ApiError(
            "TASK_COMMENT_FORBIDDEN",
            "Only the author or business owner can change this comment",
            http_status=403,
        )
    return comment


def update_task_comment(
    db: Session,
    business_id: int,
    task_id: int,
    comment_id: int,
    actor_user_id: int,
    body: str,
) -> TaskComment:
    task = _get_task_or_404(db, business_id, task_id)
    comment = _require_comment_manager(
        db,
        business_id,
        comment_id,
        actor_user_id,
    )
    if comment.task_id != task.id:
        raise ApiError(
            "TASK_COMMENT_NOT_FOUND",
            "Comment does not belong to this task",
            http_status=404,
        )
    clean_body = str(body or "").strip()
    if not clean_body:
        raise ApiError(
            "TASK_COMMENT_REQUIRED",
            "Comment body is required",
            http_status=400,
        )
    comment.body = clean_body
    comment.updated_at = _now()
    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="comment_edited",
        event_data={"comment_id": comment.id},
    )
    db.commit()
    db.refresh(comment)
    return comment


def delete_task_comment(
    db: Session,
    business_id: int,
    task_id: int,
    comment_id: int,
    actor_user_id: int,
) -> None:
    task = _get_task_or_404(db, business_id, task_id)
    comment = _require_comment_manager(
        db,
        business_id,
        comment_id,
        actor_user_id,
    )
    if comment.task_id != task.id:
        raise ApiError(
            "TASK_COMMENT_NOT_FOUND",
            "Comment does not belong to this task",
            http_status=404,
        )
    comment.deleted_at = _now()
    comment.updated_at = _now()
    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="comment_deleted",
        event_data={"comment_id": comment.id},
    )
    db.commit()


def list_task_activity(
    db: Session,
    business_id: int,
    task_id: int,
    *,
    limit: int = 100,
) -> list[TaskActivity]:
    _get_task_or_404(db, business_id, task_id)
    return (
        db.query(TaskActivity)
        .filter(
            TaskActivity.business_id == business_id,
            TaskActivity.task_id == task_id,
        )
        .order_by(TaskActivity.created_at.desc(), TaskActivity.id.desc())
        .limit(max(1, min(int(limit), 200)))
        .all()
    )
