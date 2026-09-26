"""
Core task engine.

Phase 1 implements task CRUD, completion/reopen, assignment, status,
priority, due date and project linkage on the Phase 0 domain model.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Any, Iterable, Optional
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from dateutil.rrule import rrulestr

from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.business_permission import BusinessPermission
from adapters.db.models.project import Project
from adapters.db.models.task_management import (
    Milestone,
    ProjectCycle,
    ProjectCycleTask,
    Task,
    TaskActivity,
    TaskAssignee,
    TaskComment,
    TaskLabel,
    TaskLabelLink,
    TaskRelation,
    TaskReminder,
    TaskSavedView,
    TaskStatus,
    TaskTimeEntry,
)
from adapters.db.models.user import User
from adapters.db.repositories.task_repository import TaskRepository
from app.core.business_membership import membership_is_active
from app.core.datetime_utils import resolve_display_timezone_name
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


def _normalize_recurrence(
    business_id: int,
    rule: Any,
    timezone_name: Any,
    end_at: Any,
) -> tuple[Optional[str], Optional[str], Optional[datetime]]:
    clean_rule = str(rule or "").strip()
    if not clean_rule:
        return None, None, None

    upper = clean_rule.upper()
    if upper.startswith("RRULE:"):
        clean_rule = clean_rule[6:].strip()
        upper = clean_rule.upper()
    if "COUNT=" in upper or "UNTIL=" in upper:
        raise ApiError(
            "TASK_RECURRENCE_LIMIT_UNSUPPORTED",
            "Use recurrence_end_at instead of COUNT or UNTIL in the recurrence rule",
            http_status=400,
        )
    if "FREQ=" not in upper:
        raise ApiError(
            "TASK_RECURRENCE_INVALID",
            "Recurrence rule must include FREQ",
            http_status=400,
        )

    tz_name = str(timezone_name or resolve_display_timezone_name(business_id) or "UTC").strip()
    try:
        tz = ZoneInfo(tz_name)
    except ZoneInfoNotFoundError as exc:
        raise ApiError(
            "TASK_RECURRENCE_TIMEZONE_INVALID",
            "Invalid recurrence timezone",
            http_status=400,
        ) from exc

    end = _parse_datetime(end_at)
    validation_start = _now().astimezone(tz)
    try:
        parsed = rrulestr(f"RRULE:{clean_rule}", dtstart=validation_start)
        parsed.after(validation_start, inc=False)
    except Exception as exc:
        raise ApiError(
            "TASK_RECURRENCE_INVALID",
            "Invalid recurrence rule",
            http_status=400,
        ) from exc
    return clean_rule, tz_name, end


def _sync_relative_reminders(db: Session, task: Task) -> None:
    reminders = db.query(TaskReminder).filter(
        TaskReminder.business_id == task.business_id,
        TaskReminder.task_id == task.id,
        TaskReminder.relative_to.is_not(None),
        TaskReminder.sent_at.is_(None),
    ).all()
    for reminder in reminders:
        base = task.due_at if reminder.relative_to == "due" else task.start_at
        if base is None:
            db.delete(reminder)
            continue
        reminder.remind_at = base - timedelta(minutes=int(reminder.offset_minutes or 0))


def _next_recurrence_dates(task: Task) -> tuple[Optional[datetime], Optional[datetime]]:
    if not task.recurrence_rule:
        return None, None
    tz_name = task.recurrence_timezone or resolve_display_timezone_name(task.business_id) or "UTC"
    try:
        tz = ZoneInfo(tz_name)
    except ZoneInfoNotFoundError:
        tz = ZoneInfo("UTC")

    anchor_utc = task.due_at or task.start_at or task.completed_at or _now()
    if anchor_utc.tzinfo is None:
        anchor_utc = anchor_utc.replace(tzinfo=timezone.utc)
    anchor_local = anchor_utc.astimezone(tz)
    try:
        parsed = rrulestr(f"RRULE:{task.recurrence_rule}", dtstart=anchor_local)
        next_local = parsed.after(anchor_local, inc=False)
    except Exception:
        return None, None
    if next_local is None:
        return None, None
    next_utc = next_local.astimezone(timezone.utc)
    if task.recurrence_end_at is not None:
        end = task.recurrence_end_at
        if end.tzinfo is None:
            end = end.replace(tzinfo=timezone.utc)
        if next_utc > end.astimezone(timezone.utc):
            return None, None

    if task.due_at is not None:
        next_due = next_utc
        next_start = None
        if task.start_at is not None:
            next_start = next_due - (task.due_at - task.start_at)
        return next_start, next_due
    if task.start_at is not None:
        return next_utc, None
    return None, next_utc


def _ensure_next_recurring_task(
    db: Session,
    task: Task,
    actor_user_id: int,
) -> Optional[Task]:
    if not task.recurrence_rule or task.completed_at is None:
        return None

    existing_event = db.query(TaskActivity).filter(
        TaskActivity.business_id == task.business_id,
        TaskActivity.task_id == task.id,
        TaskActivity.event_type == "recurrence_next_created",
    ).order_by(TaskActivity.id.desc()).first()
    if existing_event and isinstance(existing_event.event_data, dict):
        next_id = existing_event.event_data.get("next_task_id")
        if next_id:
            return TaskRepository(db).get_by_id(int(next_id), task.business_id)

    next_start, next_due = _next_recurrence_dates(task)
    if next_start is None and next_due is None:
        return None

    default_status = _default_status(db, task.business_id)
    repo = TaskRepository(db)
    next_task = Task(
        business_id=task.business_id,
        project_id=task.project_id,
        parent_task_id=task.parent_task_id,
        status_id=default_status.id,
        milestone_id=getattr(task, "milestone_id", None),
        title=task.title,
        description=task.description,
        priority=task.priority,
        sort_order=repo.next_sort_order(task.business_id, task.project_id),
        start_at=next_start,
        due_at=next_due,
        estimated_minutes=task.estimated_minutes,
        recurrence_rule=task.recurrence_rule,
        recurrence_timezone=task.recurrence_timezone,
        recurrence_end_at=task.recurrence_end_at,
        created_by_user_id=actor_user_id,
    )
    db.add(next_task)
    db.flush()

    for row in db.query(TaskAssignee).filter(
        TaskAssignee.business_id == task.business_id,
        TaskAssignee.task_id == task.id,
    ).all():
        db.add(TaskAssignee(
            business_id=task.business_id,
            task_id=next_task.id,
            user_id=row.user_id,
            assigned_by_user_id=actor_user_id,
        ))
    for row in db.query(TaskLabelLink).filter(
        TaskLabelLink.business_id == task.business_id,
        TaskLabelLink.task_id == task.id,
    ).all():
        db.add(TaskLabelLink(
            business_id=task.business_id,
            task_id=next_task.id,
            label_id=row.label_id,
        ))

    _record_activity(
        db,
        task=next_task,
        actor_user_id=actor_user_id,
        event_type="recurrence_task_created",
        event_data={"source_task_id": task.id},
    )
    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="recurrence_next_created",
        event_data={"next_task_id": next_task.id},
    )
    return next_task


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


def _require_milestone(
    db: Session,
    business_id: int,
    milestone_id: Optional[int],
    project_id: Optional[int],
) -> Optional[Milestone]:
    if milestone_id is None:
        return None
    if project_id is None:
        raise ApiError(
            "TASK_MILESTONE_PROJECT_REQUIRED",
            "A milestone requires the task to belong to a project",
            http_status=400,
        )
    milestone = (
        db.query(Milestone)
        .filter(
            Milestone.id == int(milestone_id),
            Milestone.business_id == business_id,
            Milestone.project_id == project_id,
        )
        .first()
    )
    if not milestone:
        raise ApiError(
            "TASK_MILESTONE_NOT_FOUND",
            "Milestone does not belong to this project",
            http_status=400,
        )
    return milestone


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
    milestone = _require_milestone(
        db,
        business_id,
        data.get("milestone_id"),
        project_id,
    )
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
    recurrence_rule, recurrence_timezone, recurrence_end_at = _normalize_recurrence(
        business_id,
        data.get("recurrence_rule"),
        data.get("recurrence_timezone"),
        data.get("recurrence_end_at"),
    )

    repo = TaskRepository(db)
    task = Task(
        business_id=business_id,
        project_id=project_id,
        parent_task_id=parent_task.id if parent_task else None,
        status_id=status.id,
        milestone_id=milestone.id if milestone else None,
        title=title,
        description=data.get("description"),
        priority=priority,
        sort_order=repo.next_sort_order(business_id, project.id if project else None),
        start_at=start_at,
        due_at=due_at,
        estimated_minutes=data.get("estimated_minutes"),
        recurrence_rule=recurrence_rule,
        recurrence_timezone=recurrence_timezone,
        recurrence_end_at=recurrence_end_at,
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

    label_ids = _normalize_label_ids(data.get("label_ids"))
    replace_task_labels(
        db,
        task=task,
        label_ids=label_ids,
        actor_user_id=actor_user_id,
        commit=False,
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
    was_completed = task.completed_at is not None

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
    proposed_milestone_id = (
        data.get("milestone_id")
        if "milestone_id" in data
        else task.milestone_id
    )
    if (
        "project_id" in data
        and "milestone_id" not in data
        and proposed_project_id != task.project_id
    ):
        proposed_milestone_id = None
    milestone = _require_milestone(
        db,
        business_id,
        proposed_milestone_id,
        proposed_project_id,
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

    next_milestone_id = milestone.id if milestone else None
    if next_milestone_id != task.milestone_id:
        changes["milestone_id"] = {
            "from": task.milestone_id,
            "to": next_milestone_id,
        }
        task.milestone_id = next_milestone_id

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

    if "recurrence_rule" in data or "recurrence_timezone" in data or "recurrence_end_at" in data:
        recurrence_rule, recurrence_timezone, recurrence_end_at = _normalize_recurrence(
            business_id,
            data.get("recurrence_rule", task.recurrence_rule),
            data.get("recurrence_timezone", task.recurrence_timezone),
            data.get("recurrence_end_at", task.recurrence_end_at),
        )
        task.recurrence_rule = recurrence_rule
        task.recurrence_timezone = recurrence_timezone
        task.recurrence_end_at = recurrence_end_at

    if "start_at" in data or "due_at" in data:
        _sync_relative_reminders(db, task)

    task.updated_at = _now()

    if changes:
        _record_activity(
            db,
            task=task,
            actor_user_id=actor_user_id,
            event_type="task_updated",
            event_data=changes,
        )

    if "label_ids" in data:
        replace_task_labels(
            db,
            task=task,
            label_ids=data.get("label_ids") or [],
            actor_user_id=actor_user_id,
            commit=False,
        )

    if "assignee_user_ids" in data:
        replace_task_assignees(
            db,
            task=task,
            assignee_user_ids=data.get("assignee_user_ids") or [],
            actor_user_id=actor_user_id,
            commit=False,
        )

    if task.completed_at is not None and not was_completed:
        _ensure_next_recurring_task(db, task, actor_user_id)

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
    _ensure_next_recurring_task(db, task, actor_user_id)
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
    was_completed = task.completed_at is not None

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
    if task.completed_at is not None and not was_completed:
        _ensure_next_recurring_task(db, task, actor_user_id)
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



def _normalize_label_ids(values: Optional[Iterable[int]]) -> list[int]:
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


def replace_task_labels(
    db: Session,
    *,
    task: Task,
    label_ids: Iterable[int],
    actor_user_id: Optional[int],
    commit: bool = True,
) -> list[int]:
    new_ids = _normalize_label_ids(label_ids)
    if new_ids:
        labels = db.query(TaskLabel).filter(
            TaskLabel.business_id == task.business_id,
            TaskLabel.id.in_(new_ids),
        ).all()
        if len({item.id for item in labels}) != len(new_ids):
            raise ApiError(
                "TASK_LABEL_NOT_FOUND",
                "One or more task labels do not belong to this business",
                http_status=400,
            )
    current_rows = db.query(TaskLabelLink).filter(
        TaskLabelLink.business_id == task.business_id,
        TaskLabelLink.task_id == task.id,
    ).all()
    current_ids = [row.label_id for row in current_rows]
    if set(current_ids) == set(new_ids):
        return current_ids
    db.query(TaskLabelLink).filter(
        TaskLabelLink.business_id == task.business_id,
        TaskLabelLink.task_id == task.id,
    ).delete(synchronize_session=False)
    for label_id in new_ids:
        db.add(TaskLabelLink(
            business_id=task.business_id,
            task_id=task.id,
            label_id=label_id,
        ))
    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="labels_changed",
        event_data={"from": current_ids, "to": new_ids},
    )
    if commit:
        db.commit()
    return new_ids


def list_task_labels(db: Session, business_id: int) -> list[TaskLabel]:
    _require_business(db, business_id)
    return db.query(TaskLabel).filter(
        TaskLabel.business_id == business_id
    ).order_by(TaskLabel.name.asc(), TaskLabel.id.asc()).all()


def create_task_label(
    db: Session,
    business_id: int,
    name: str,
    color: Optional[str],
    description: Optional[str],
) -> TaskLabel:
    _require_business(db, business_id)
    clean_name = str(name or "").strip()
    if not clean_name:
        raise ApiError("TASK_LABEL_NAME_REQUIRED", "Label name is required", http_status=400)
    if db.query(TaskLabel.id).filter(
        TaskLabel.business_id == business_id,
        TaskLabel.name == clean_name,
    ).first():
        raise ApiError("TASK_LABEL_EXISTS", "A label with this name already exists", http_status=409)
    label = TaskLabel(
        business_id=business_id,
        name=clean_name,
        color=color,
        description=description,
    )
    db.add(label)
    db.commit()
    db.refresh(label)
    return label


def update_task_label(
    db: Session,
    business_id: int,
    label_id: int,
    data: dict[str, Any],
) -> TaskLabel:
    label = db.query(TaskLabel).filter(
        TaskLabel.business_id == business_id,
        TaskLabel.id == label_id,
    ).first()
    if not label:
        raise ApiError("TASK_LABEL_NOT_FOUND", "Task label not found", http_status=404)
    if "name" in data:
        clean_name = str(data.get("name") or "").strip()
        if db.query(TaskLabel.id).filter(
            TaskLabel.business_id == business_id,
            TaskLabel.name == clean_name,
            TaskLabel.id != label.id,
        ).first():
            raise ApiError("TASK_LABEL_EXISTS", "A label with this name already exists", http_status=409)
        label.name = clean_name
    if "color" in data:
        label.color = data.get("color")
    if "description" in data:
        label.description = data.get("description")
    label.updated_at = _now()
    db.commit()
    db.refresh(label)
    return label


def delete_task_label(db: Session, business_id: int, label_id: int) -> None:
    label = db.query(TaskLabel).filter(
        TaskLabel.business_id == business_id,
        TaskLabel.id == label_id,
    ).first()
    if not label:
        raise ApiError("TASK_LABEL_NOT_FOUND", "Task label not found", http_status=404)
    db.delete(label)
    db.commit()


def list_saved_task_views(
    db: Session,
    business_id: int,
    user_id: int,
) -> list[TaskSavedView]:
    _require_business(db, business_id)
    return db.query(TaskSavedView).filter(
        TaskSavedView.business_id == business_id,
        (
            (TaskSavedView.user_id == user_id)
            | (TaskSavedView.is_shared.is_(True))
        ),
    ).order_by(TaskSavedView.name.asc(), TaskSavedView.id.asc()).all()


def create_saved_task_view(
    db: Session,
    business_id: int,
    user_id: int,
    data: dict[str, Any],
) -> TaskSavedView:
    _require_business(db, business_id)
    project_id = data.get("project_id")
    if project_id is not None:
        _require_project(db, business_id, project_id)
    name = str(data.get("name") or "").strip()
    if db.query(TaskSavedView.id).filter(
        TaskSavedView.business_id == business_id,
        TaskSavedView.user_id == user_id,
        TaskSavedView.name == name,
    ).first():
        raise ApiError("TASK_VIEW_EXISTS", "A saved view with this name already exists", http_status=409)
    view = TaskSavedView(
        business_id=business_id,
        user_id=user_id,
        project_id=project_id,
        name=name,
        view_type=str(data.get("view_type") or "list"),
        filters_json=dict(data.get("filters") or {}),
        sort_json=dict(data.get("sort") or {}),
        is_shared=bool(data.get("is_shared", False)),
    )
    db.add(view)
    db.commit()
    db.refresh(view)
    return view


def update_saved_task_view(
    db: Session,
    business_id: int,
    user_id: int,
    view_id: int,
    data: dict[str, Any],
) -> TaskSavedView:
    view = db.query(TaskSavedView).filter(
        TaskSavedView.id == view_id,
        TaskSavedView.business_id == business_id,
    ).first()
    if not view:
        raise ApiError("TASK_VIEW_NOT_FOUND", "Saved view not found", http_status=404)
    if view.user_id != user_id:
        raise ApiError("TASK_VIEW_FORBIDDEN", "Only the view owner can edit this view", http_status=403)
    if "name" in data:
        name = str(data.get("name") or "").strip()
        if db.query(TaskSavedView.id).filter(
            TaskSavedView.business_id == business_id,
            TaskSavedView.user_id == user_id,
            TaskSavedView.name == name,
            TaskSavedView.id != view.id,
        ).first():
            raise ApiError("TASK_VIEW_EXISTS", "A saved view with this name already exists", http_status=409)
        view.name = name
    if "project_id" in data:
        project_id = data.get("project_id")
        if project_id is not None:
            _require_project(db, business_id, project_id)
        view.project_id = project_id
    if "view_type" in data:
        view.view_type = str(data.get("view_type") or "list")
    if "filters" in data:
        view.filters_json = dict(data.get("filters") or {})
    if "sort" in data:
        view.sort_json = dict(data.get("sort") or {})
    if "is_shared" in data:
        view.is_shared = bool(data.get("is_shared"))
    view.updated_at = _now()
    db.commit()
    db.refresh(view)
    return view


def delete_saved_task_view(
    db: Session,
    business_id: int,
    user_id: int,
    view_id: int,
) -> None:
    view = db.query(TaskSavedView).filter(
        TaskSavedView.id == view_id,
        TaskSavedView.business_id == business_id,
    ).first()
    if not view:
        raise ApiError("TASK_VIEW_NOT_FOUND", "Saved view not found", http_status=404)
    if view.user_id != user_id:
        raise ApiError("TASK_VIEW_FORBIDDEN", "Only the view owner can delete this view", http_status=403)
    db.delete(view)
    db.commit()



def list_task_reminders(
    db: Session,
    business_id: int,
    task_id: int,
) -> list[TaskReminder]:
    _get_task_or_404(db, business_id, task_id)
    return db.query(TaskReminder).filter(
        TaskReminder.business_id == business_id,
        TaskReminder.task_id == task_id,
    ).order_by(TaskReminder.remind_at.asc(), TaskReminder.id.asc()).all()


def create_task_reminder(
    db: Session,
    business_id: int,
    task_id: int,
    actor_user_id: int,
    data: dict[str, Any],
) -> TaskReminder:
    task = _get_task_or_404(db, business_id, task_id)
    business = _require_business(db, business_id)
    user_id = int(data.get("user_id") or actor_user_id)
    _require_business_member(db, business, user_id)

    relative_to = str(data.get("relative_to") or "").strip().lower() or None
    offset_minutes = data.get("offset_minutes")
    remind_at = _parse_datetime(data.get("remind_at"))

    if relative_to is not None:
        if relative_to not in {"due", "start"}:
            raise ApiError(
                "TASK_REMINDER_RELATIVE_INVALID",
                "Reminder relative_to must be due or start",
                http_status=400,
            )
        offset = int(offset_minutes or 0)
        base = task.due_at if relative_to == "due" else task.start_at
        if base is None:
            raise ApiError(
                "TASK_REMINDER_DATE_REQUIRED",
                "Task date is required for a relative reminder",
                http_status=400,
            )
        remind_at = base - timedelta(minutes=offset)
        offset_minutes = offset
    elif remind_at is None:
        raise ApiError(
            "TASK_REMINDER_TIME_REQUIRED",
            "Reminder time is required",
            http_status=400,
        )

    reminder = TaskReminder(
        business_id=business_id,
        task_id=task.id,
        user_id=user_id,
        remind_at=remind_at,
        relative_to=relative_to,
        offset_minutes=int(offset_minutes) if offset_minutes is not None else None,
    )
    db.add(reminder)
    db.flush()
    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="reminder_added",
        event_data={"reminder_id": reminder.id, "user_id": user_id},
    )
    db.commit()
    db.refresh(reminder)
    return reminder


def delete_task_reminder(
    db: Session,
    business_id: int,
    task_id: int,
    reminder_id: int,
    actor_user_id: int,
) -> None:
    task = _get_task_or_404(db, business_id, task_id)
    reminder = db.query(TaskReminder).filter(
        TaskReminder.id == reminder_id,
        TaskReminder.business_id == business_id,
        TaskReminder.task_id == task.id,
    ).first()
    if not reminder:
        raise ApiError("TASK_REMINDER_NOT_FOUND", "Task reminder not found", http_status=404)
    business = _require_business(db, business_id)
    if reminder.user_id != actor_user_id and int(business.owner_id) != int(actor_user_id):
        raise ApiError(
            "TASK_REMINDER_FORBIDDEN",
            "Only the reminder owner or business owner can delete it",
            http_status=403,
        )
    db.delete(reminder)
    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="reminder_removed",
        event_data={"reminder_id": reminder_id},
    )
    db.commit()



def list_task_cycles(
    db: Session,
    business_id: int,
    task_id: int,
) -> list[ProjectCycle]:
    task = _get_task_or_404(db, business_id, task_id)
    if task.project_id is None:
        return []
    return (
        db.query(ProjectCycle)
        .join(
            ProjectCycleTask,
            ProjectCycleTask.cycle_id == ProjectCycle.id,
        )
        .filter(
            ProjectCycleTask.business_id == business_id,
            ProjectCycleTask.task_id == task.id,
            ProjectCycle.business_id == business_id,
            ProjectCycle.project_id == task.project_id,
        )
        .order_by(ProjectCycle.start_at.desc().nullslast(), ProjectCycle.id.desc())
        .all()
    )


def replace_task_cycles(
    db: Session,
    business_id: int,
    task_id: int,
    actor_user_id: int,
    cycle_ids: Iterable[int],
) -> list[ProjectCycle]:
    task = _get_task_or_404(db, business_id, task_id)
    ids: list[int] = []
    seen: set[int] = set()
    for raw in cycle_ids:
        value = int(raw)
        if value <= 0 or value in seen:
            continue
        seen.add(value)
        ids.append(value)

    if ids and task.project_id is None:
        raise ApiError(
            "TASK_CYCLE_PROJECT_REQUIRED",
            "A task must belong to a project before assigning a cycle",
            http_status=400,
        )

    cycles = []
    if ids:
        cycles = (
            db.query(ProjectCycle)
            .filter(
                ProjectCycle.business_id == business_id,
                ProjectCycle.project_id == task.project_id,
                ProjectCycle.id.in_(ids),
            )
            .all()
        )
        if len({cycle.id for cycle in cycles}) != len(ids):
            raise ApiError(
                "TASK_CYCLE_NOT_FOUND",
                "One or more cycles do not belong to the task project",
                http_status=400,
            )

    current_rows = db.query(ProjectCycleTask).filter(
        ProjectCycleTask.business_id == business_id,
        ProjectCycleTask.task_id == task.id,
    ).all()
    current_ids = [row.cycle_id for row in current_rows]
    if set(current_ids) == set(ids):
        return list_task_cycles(db, business_id, task_id)

    db.query(ProjectCycleTask).filter(
        ProjectCycleTask.business_id == business_id,
        ProjectCycleTask.task_id == task.id,
    ).delete(synchronize_session=False)
    for cycle_id in ids:
        db.add(
            ProjectCycleTask(
                business_id=business_id,
                cycle_id=cycle_id,
                task_id=task.id,
            )
        )
    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="cycles_changed",
        event_data={"from": current_ids, "to": ids},
    )
    db.commit()
    return list_task_cycles(db, business_id, task_id)



def _time_entry_can_manage(
    db: Session,
    business_id: int,
    actor_user_id: int,
    entry: TaskTimeEntry,
) -> bool:
    if int(entry.user_id) == int(actor_user_id):
        return True
    business = _require_business(db, business_id)
    return int(business.owner_id) == int(actor_user_id)


def get_active_time_entry(
    db: Session,
    business_id: int,
    user_id: int,
) -> Optional[TaskTimeEntry]:
    return (
        db.query(TaskTimeEntry)
        .filter(
            TaskTimeEntry.business_id == business_id,
            TaskTimeEntry.user_id == user_id,
            TaskTimeEntry.ended_at.is_(None),
        )
        .order_by(TaskTimeEntry.started_at.desc(), TaskTimeEntry.id.desc())
        .first()
    )


def list_time_entries(
    db: Session,
    business_id: int,
    *,
    task_id: Optional[int] = None,
    project_id: Optional[int] = None,
    user_id: Optional[int] = None,
    limit: int = 200,
) -> list[TaskTimeEntry]:
    _require_business(db, business_id)
    query = db.query(TaskTimeEntry).filter(
        TaskTimeEntry.business_id == business_id
    )
    if task_id is not None:
        _get_task_or_404(db, business_id, task_id)
        query = query.filter(TaskTimeEntry.task_id == task_id)
    if project_id is not None:
        _require_project(db, business_id, project_id)
        query = query.join(Task, TaskTimeEntry.task_id == Task.id).filter(
            Task.business_id == business_id,
            Task.project_id == project_id,
            Task.deleted_at.is_(None),
        )
    if user_id is not None:
        query = query.filter(TaskTimeEntry.user_id == user_id)
    return (
        query.order_by(
            TaskTimeEntry.started_at.desc(),
            TaskTimeEntry.id.desc(),
        )
        .limit(max(1, min(int(limit), 500)))
        .all()
    )


def start_task_timer(
    db: Session,
    business_id: int,
    task_id: int,
    actor_user_id: int,
    *,
    description: Optional[str] = None,
    billable: bool = False,
) -> TaskTimeEntry:
    task = _get_task_or_404(db, business_id, task_id)
    business = _require_business(db, business_id)
    _require_business_member(db, business, actor_user_id)

    active = get_active_time_entry(db, business_id, actor_user_id)
    if active is not None:
        raise ApiError(
            "TASK_TIMER_ALREADY_ACTIVE",
            f"An active timer already exists for task {active.task_id}",
            http_status=409,
        )

    entry = TaskTimeEntry(
        business_id=business_id,
        task_id=task.id,
        user_id=actor_user_id,
        started_at=_now(),
        ended_at=None,
        duration_seconds=None,
        description=(description or "").strip() or None,
        billable=bool(billable),
    )
    db.add(entry)
    db.flush()
    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="timer_started",
        event_data={"time_entry_id": entry.id},
    )
    db.commit()
    db.refresh(entry)
    return entry


def stop_active_timer(
    db: Session,
    business_id: int,
    actor_user_id: int,
) -> TaskTimeEntry:
    entry = get_active_time_entry(db, business_id, actor_user_id)
    if entry is None:
        raise ApiError(
            "TASK_TIMER_NOT_ACTIVE",
            "No active timer was found",
            http_status=404,
        )
    task = _get_task_or_404(db, business_id, entry.task_id)
    ended_at = _now()
    started_at = entry.started_at
    if started_at.tzinfo is None:
        started_at = started_at.replace(tzinfo=timezone.utc)
    entry.ended_at = ended_at
    entry.duration_seconds = max(
        0,
        int((ended_at - started_at.astimezone(timezone.utc)).total_seconds()),
    )
    entry.updated_at = ended_at
    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="timer_stopped",
        event_data={
            "time_entry_id": entry.id,
            "duration_seconds": entry.duration_seconds,
        },
    )
    db.commit()
    db.refresh(entry)
    return entry


def create_manual_time_entry(
    db: Session,
    business_id: int,
    task_id: int,
    actor_user_id: int,
    data: dict[str, Any],
) -> TaskTimeEntry:
    task = _get_task_or_404(db, business_id, task_id)
    business = _require_business(db, business_id)
    _require_business_member(db, business, actor_user_id)

    started_at = _parse_datetime(data.get("started_at"))
    if started_at is None:
        raise ApiError(
            "TASK_TIME_START_REQUIRED",
            "Time entry start is required",
            http_status=400,
        )
    ended_at = _parse_datetime(data.get("ended_at"))
    duration_minutes = data.get("duration_minutes")
    if ended_at is None and duration_minutes is not None:
        ended_at = started_at + timedelta(minutes=int(duration_minutes))
    if ended_at is None:
        raise ApiError(
            "TASK_TIME_END_REQUIRED",
            "Manual time entry requires an end time or duration",
            http_status=400,
        )
    if ended_at < started_at:
        raise ApiError(
            "TASK_TIME_INVALID_RANGE",
            "Time entry end cannot be before start",
            http_status=400,
        )

    entry = TaskTimeEntry(
        business_id=business_id,
        task_id=task.id,
        user_id=actor_user_id,
        started_at=started_at,
        ended_at=ended_at,
        duration_seconds=max(
            0,
            int((ended_at - started_at).total_seconds()),
        ),
        description=(data.get("description") or "").strip() or None,
        billable=bool(data.get("billable", False)),
    )
    db.add(entry)
    db.flush()
    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="time_entry_added",
        event_data={
            "time_entry_id": entry.id,
            "duration_seconds": entry.duration_seconds,
        },
    )
    db.commit()
    db.refresh(entry)
    return entry


def update_time_entry(
    db: Session,
    business_id: int,
    entry_id: int,
    actor_user_id: int,
    data: dict[str, Any],
) -> TaskTimeEntry:
    entry = (
        db.query(TaskTimeEntry)
        .filter(
            TaskTimeEntry.id == entry_id,
            TaskTimeEntry.business_id == business_id,
        )
        .first()
    )
    if not entry:
        raise ApiError(
            "TASK_TIME_ENTRY_NOT_FOUND",
            "Time entry not found",
            http_status=404,
        )
    if entry.ended_at is None:
        raise ApiError(
            "TASK_TIME_ENTRY_ACTIVE",
            "Stop the active timer before editing it",
            http_status=409,
        )
    if not _time_entry_can_manage(
        db,
        business_id,
        actor_user_id,
        entry,
    ):
        raise ApiError(
            "TASK_TIME_ENTRY_FORBIDDEN",
            "Only the entry owner or business owner can edit it",
            http_status=403,
        )

    started_at = (
        _parse_datetime(data.get("started_at"))
        if "started_at" in data
        else entry.started_at
    )
    ended_at = (
        _parse_datetime(data.get("ended_at"))
        if "ended_at" in data
        else entry.ended_at
    )
    if started_at is None or ended_at is None or ended_at < started_at:
        raise ApiError(
            "TASK_TIME_INVALID_RANGE",
            "Time entry start/end range is invalid",
            http_status=400,
        )
    entry.started_at = started_at
    entry.ended_at = ended_at
    entry.duration_seconds = max(
        0,
        int((ended_at - started_at).total_seconds()),
    )
    if "description" in data:
        entry.description = (data.get("description") or "").strip() or None
    if "billable" in data:
        entry.billable = bool(data.get("billable"))
    entry.updated_at = _now()
    task = _get_task_or_404(db, business_id, entry.task_id)
    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="time_entry_updated",
        event_data={
            "time_entry_id": entry.id,
            "duration_seconds": entry.duration_seconds,
        },
    )
    db.commit()
    db.refresh(entry)
    return entry


def delete_time_entry(
    db: Session,
    business_id: int,
    entry_id: int,
    actor_user_id: int,
) -> None:
    entry = (
        db.query(TaskTimeEntry)
        .filter(
            TaskTimeEntry.id == entry_id,
            TaskTimeEntry.business_id == business_id,
        )
        .first()
    )
    if not entry:
        raise ApiError(
            "TASK_TIME_ENTRY_NOT_FOUND",
            "Time entry not found",
            http_status=404,
        )
    if entry.ended_at is None:
        raise ApiError(
            "TASK_TIME_ENTRY_ACTIVE",
            "Stop the active timer before deleting it",
            http_status=409,
        )
    if not _time_entry_can_manage(
        db,
        business_id,
        actor_user_id,
        entry,
    ):
        raise ApiError(
            "TASK_TIME_ENTRY_FORBIDDEN",
            "Only the entry owner or business owner can delete it",
            http_status=403,
        )
    task = _get_task_or_404(db, business_id, entry.task_id)
    event_data = {
        "time_entry_id": entry.id,
        "duration_seconds": entry.duration_seconds,
    }
    db.delete(entry)
    _record_activity(
        db,
        task=task,
        actor_user_id=actor_user_id,
        event_type="time_entry_deleted",
        event_data=event_data,
    )
    db.commit()
