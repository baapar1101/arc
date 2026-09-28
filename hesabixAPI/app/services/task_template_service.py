"""Native reusable project/task template service."""

from __future__ import annotations

from datetime import date, datetime, time, timedelta, timezone
from typing import Any, Optional

from sqlalchemy.orm import Session

from adapters.db.models.project import Project
from adapters.db.models.task_management import (
    Task,
    TaskAssignee,
    TaskLabelLink,
    TaskProjectTemplate,
)
from app.core.responses import ApiError
from app.services.project_service import create_project
from app.services.task_management_service import (
    add_task_entity_link,
    create_task,
    ensure_default_task_statuses,
)


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _parse_date(value: Any) -> Optional[date]:
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).date()
        except ValueError as exc:
            raise ApiError(
                "TASK_TEMPLATE_DATE_INVALID",
                "Invalid template start date",
                http_status=400,
            ) from exc
    raise ApiError(
        "TASK_TEMPLATE_DATE_INVALID",
        "Invalid template start date",
        http_status=400,
    )


def _format_time(value: Optional[datetime]) -> Optional[str]:
    if value is None:
        return None
    aware = value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
    return aware.astimezone(timezone.utc).strftime("%H:%M:%S")


def _offset(value: Optional[datetime], base: date) -> Optional[int]:
    if value is None:
        return None
    aware = value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
    return (aware.astimezone(timezone.utc).date() - base).days


def _build_datetime(
    base: date,
    offset_days: Any,
    clock: Any,
    default_clock: time,
) -> Optional[datetime]:
    if offset_days is None:
        return None
    target = base + timedelta(days=int(offset_days))
    parsed_time = default_clock
    if clock:
        try:
            parsed_time = time.fromisoformat(str(clock))
        except ValueError:
            parsed_time = default_clock
    return datetime.combine(target, parsed_time, tzinfo=timezone.utc)


def _get_template(
    db: Session,
    business_id: int,
    template_id: int,
) -> TaskProjectTemplate:
    row = db.query(TaskProjectTemplate).filter(
        TaskProjectTemplate.id == template_id,
        TaskProjectTemplate.business_id == business_id,
    ).first()
    if row is None:
        raise ApiError(
            "TASK_TEMPLATE_NOT_FOUND",
            "Project/task template not found",
            http_status=404,
        )
    return row


def list_project_task_templates(
    db: Session,
    business_id: int,
    *,
    include_inactive: bool = False,
) -> list[TaskProjectTemplate]:
    query = db.query(TaskProjectTemplate).filter(
        TaskProjectTemplate.business_id == business_id,
    )
    if not include_inactive:
        query = query.filter(TaskProjectTemplate.is_active.is_(True))
    return query.order_by(
        TaskProjectTemplate.name.asc(),
        TaskProjectTemplate.id.asc(),
    ).all()


def create_project_task_template(
    db: Session,
    business_id: int,
    actor_user_id: int,
    data: dict[str, Any],
) -> TaskProjectTemplate:
    name = str(data.get("name") or "").strip()
    if not name:
        raise ApiError(
            "TASK_TEMPLATE_NAME_REQUIRED",
            "Template name is required",
            http_status=400,
        )
    duplicate = db.query(TaskProjectTemplate.id).filter(
        TaskProjectTemplate.business_id == business_id,
        TaskProjectTemplate.name == name,
    ).first()
    if duplicate:
        raise ApiError(
            "TASK_TEMPLATE_EXISTS",
            "A template with this name already exists",
            http_status=409,
        )
    tasks = list(data.get("tasks") or [])
    if len(tasks) > 500:
        raise ApiError(
            "TASK_TEMPLATE_TOO_LARGE",
            "Template cannot contain more than 500 tasks",
            http_status=400,
        )
    row = TaskProjectTemplate(
        business_id=business_id,
        name=name,
        description=data.get("description"),
        project_defaults_json=dict(data.get("project_defaults") or {}),
        tasks_json=tasks,
        is_active=bool(data.get("is_active", True)),
        created_by_user_id=actor_user_id,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def update_project_task_template(
    db: Session,
    business_id: int,
    template_id: int,
    data: dict[str, Any],
) -> TaskProjectTemplate:
    row = _get_template(db, business_id, template_id)
    if "name" in data:
        name = str(data.get("name") or "").strip()
        if not name:
            raise ApiError(
                "TASK_TEMPLATE_NAME_REQUIRED",
                "Template name is required",
                http_status=400,
            )
        duplicate = db.query(TaskProjectTemplate.id).filter(
            TaskProjectTemplate.business_id == business_id,
            TaskProjectTemplate.name == name,
            TaskProjectTemplate.id != row.id,
        ).first()
        if duplicate:
            raise ApiError(
                "TASK_TEMPLATE_EXISTS",
                "A template with this name already exists",
                http_status=409,
            )
        row.name = name
    if "description" in data:
        row.description = data.get("description")
    if "project_defaults" in data:
        row.project_defaults_json = dict(data.get("project_defaults") or {})
    if "tasks" in data:
        tasks = list(data.get("tasks") or [])
        if len(tasks) > 500:
            raise ApiError(
                "TASK_TEMPLATE_TOO_LARGE",
                "Template cannot contain more than 500 tasks",
                http_status=400,
            )
        row.tasks_json = tasks
    if "is_active" in data:
        row.is_active = bool(data.get("is_active"))
    row.updated_at = _utc_now()
    db.commit()
    db.refresh(row)
    return row


def delete_project_task_template(
    db: Session,
    business_id: int,
    template_id: int,
) -> None:
    row = _get_template(db, business_id, template_id)
    db.delete(row)
    db.commit()


def snapshot_project_as_template(
    db: Session,
    business_id: int,
    project_id: int,
    actor_user_id: int,
    *,
    name: str,
    description: Optional[str] = None,
) -> TaskProjectTemplate:
    project = db.query(Project).filter(
        Project.id == project_id,
        Project.business_id == business_id,
    ).first()
    if project is None:
        raise ApiError("PROJECT_NOT_FOUND", "Project not found", http_status=404)

    tasks = db.query(Task).filter(
        Task.business_id == business_id,
        Task.project_id == project_id,
        Task.deleted_at.is_(None),
    ).order_by(Task.sort_order.asc(), Task.id.asc()).all()

    dated = [
        value
        for task in tasks
        for value in (task.start_at, task.due_at)
        if value is not None
    ]
    if project.start_date is not None:
        base = project.start_date
    elif dated:
        base = min(
            (
                value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
            ).astimezone(timezone.utc).date()
            for value in dated
        )
    else:
        base = date.today()

    task_keys = {task.id: f"task-{index + 1}" for index, task in enumerate(tasks)}
    task_specs: list[dict[str, Any]] = []

    for task in tasks:
        assignees = [
            int(row[0])
            for row in db.query(TaskAssignee.user_id).filter(
                TaskAssignee.business_id == business_id,
                TaskAssignee.task_id == task.id,
            ).all()
        ]
        labels = [
            int(row[0])
            for row in db.query(TaskLabelLink.label_id).filter(
                TaskLabelLink.business_id == business_id,
                TaskLabelLink.task_id == task.id,
            ).all()
        ]
        task_specs.append(
            {
                "key": task_keys[task.id],
                "parent_key": task_keys.get(task.parent_task_id),
                "title": task.title,
                "description": task.description,
                "priority": task.priority,
                "status_key": task.status.key if task.status else "todo",
                "start_offset_days": _offset(task.start_at, base),
                "start_time": _format_time(task.start_at),
                "due_offset_days": _offset(task.due_at, base),
                "due_time": _format_time(task.due_at),
                "estimated_minutes": task.estimated_minutes,
                "assignee_user_ids": assignees,
                "label_ids": labels,
                "recurrence_rule": task.recurrence_rule,
                "recurrence_timezone": task.recurrence_timezone,
            }
        )

    project_defaults = {
        "description": project.description,
        "status": "active",
        "budget": float(project.budget) if project.budget is not None else None,
        "currency_id": project.currency_id,
        "extra_info": project.extra_info or {},
        "duration_days": (
            (project.end_date - project.start_date).days
            if project.start_date is not None and project.end_date is not None
            else None
        ),
    }
    return create_project_task_template(
        db,
        business_id,
        actor_user_id,
        {
            "name": name,
            "description": description or project.description,
            "project_defaults": project_defaults,
            "tasks": task_specs,
            "is_active": True,
        },
    )


def instantiate_project_task_template(
    db: Session,
    business_id: int,
    template_id: int,
    actor_user_id: int,
    data: dict[str, Any],
) -> dict[str, Any]:
    template = _get_template(db, business_id, template_id)
    if not template.is_active:
        raise ApiError(
            "TASK_TEMPLATE_INACTIVE",
            "Template is inactive",
            http_status=400,
        )

    project_id = data.get("project_id")
    start_date = _parse_date(data.get("start_date")) or date.today()

    if project_id is not None:
        project = db.query(Project).filter(
            Project.id == int(project_id),
            Project.business_id == business_id,
        ).first()
        if project is None:
            raise ApiError("PROJECT_NOT_FOUND", "Project not found", http_status=404)
        if data.get("start_date") is None and project.start_date is not None:
            start_date = project.start_date
    else:
        code = str(data.get("project_code") or "").strip()
        name = str(data.get("project_name") or "").strip()
        if not code or not name:
            raise ApiError(
                "TASK_TEMPLATE_PROJECT_REQUIRED",
                "project_code and project_name are required for a new project",
                http_status=400,
            )
        defaults = dict(template.project_defaults_json or {})
        duration_days = defaults.pop("duration_days", None)
        project_data = {
            **defaults,
            "code": code,
            "name": name,
            "start_date": start_date,
            "end_date": (
                start_date + timedelta(days=int(duration_days))
                if duration_days is not None
                else None
            ),
            "person_id": data.get("person_id"),
            "manager_user_id": data.get("manager_user_id"),
            "status": "active",
            "is_active": True,
        }
        project = create_project(
            db,
            business_id,
            actor_user_id,
            project_data,
        )

    statuses = ensure_default_task_statuses(db, business_id)
    status_by_key = {item.key: item.id for item in statuses}

    pending = [dict(item) for item in list(template.tasks_json or [])]
    if len(pending) > 500:
        raise ApiError(
            "TASK_TEMPLATE_TOO_LARGE",
            "Template cannot contain more than 500 tasks",
            http_status=400,
        )

    created: dict[str, Task] = {}
    created_order: list[Task] = []
    safety = 0

    while pending:
        safety += 1
        if safety > 550:
            raise ApiError(
                "TASK_TEMPLATE_PARENT_INVALID",
                "Template contains an invalid parent hierarchy",
                http_status=400,
            )
        progressed = False
        for item in list(pending):
            key = str(item.get("key") or "").strip()
            if not key:
                raise ApiError(
                    "TASK_TEMPLATE_KEY_REQUIRED",
                    "Every template task needs a key",
                    http_status=400,
                )
            if key in created:
                raise ApiError(
                    "TASK_TEMPLATE_DUPLICATE_KEY",
                    "Template task keys must be unique",
                    http_status=400,
                )
            parent_key = item.get("parent_key")
            if parent_key and str(parent_key) not in created:
                continue

            task_data = {
                "project_id": project.id,
                "parent_task_id": (
                    created[str(parent_key)].id if parent_key else None
                ),
                "title": str(item.get("title") or "").strip(),
                "description": item.get("description"),
                "priority": item.get("priority") or "normal",
                "status_id": status_by_key.get(
                    str(item.get("status_key") or "todo"),
                    status_by_key.get("todo"),
                ),
                "start_at": _build_datetime(
                    start_date,
                    item.get("start_offset_days"),
                    item.get("start_time"),
                    time(9, 0),
                ),
                "due_at": _build_datetime(
                    start_date,
                    item.get("due_offset_days"),
                    item.get("due_time"),
                    time(17, 0),
                ),
                "estimated_minutes": item.get("estimated_minutes"),
                "assignee_user_ids": list(item.get("assignee_user_ids") or []),
                "label_ids": list(item.get("label_ids") or []),
                "recurrence_rule": item.get("recurrence_rule"),
                "recurrence_timezone": item.get("recurrence_timezone"),
            }
            task = create_task(
                db,
                business_id,
                actor_user_id,
                task_data,
            )
            created[key] = task
            created_order.append(task)
            pending.remove(item)
            progressed = True

        if not progressed:
            raise ApiError(
                "TASK_TEMPLATE_PARENT_INVALID",
                "Template contains a missing or cyclic parent reference",
                http_status=400,
            )

    link_type = data.get("link_entity_type")
    link_id = data.get("link_entity_id")
    if link_type and link_id:
        relationship = str(data.get("relationship_type") or "related")
        for task in created_order:
            add_task_entity_link(
                db,
                business_id,
                task.id,
                actor_user_id,
                entity_type=str(link_type),
                entity_id=link_id,
                relationship_type=relationship,
            )

    return {
        "template_id": template.id,
        "project_id": project.id,
        "project_code": project.code,
        "project_name": project.name,
        "task_ids": [task.id for task in created_order],
        "task_count": len(created_order),
    }
