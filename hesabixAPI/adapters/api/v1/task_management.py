from __future__ import annotations

from datetime import datetime
from typing import Any, Optional

from fastapi import APIRouter, Depends, Path, Query, Request
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.task_management import (
    TaskAssigneesRequest,
    TaskCommentCreateRequest,
    TaskCommentUpdateRequest,
    TaskCreateRequest,
    TaskLabelCreateRequest,
    TaskLabelUpdateRequest,
    TaskLabelsAssignRequest,
    TaskMoveRequest,
    TaskRelationCreateRequest,
    TaskReminderCreateRequest,
    TaskSavedViewCreateRequest,
    TaskSavedViewUpdateRequest,
    TaskSubtaskCreateRequest,
    TaskUpdateRequest,
)
from adapters.db.models.task_management import Task, TaskStatus
from adapters.db.repositories.task_repository import TaskRepository
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_access
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.services.task_management_service import (
    add_task_comment,
    add_task_relation,
    create_saved_task_view,
    create_task_label,
    complete_task,
    create_task_reminder,
    create_subtask,
    create_task,
    delete_saved_task_view,
    delete_task_comment,
    delete_task_reminder,
    delete_task_label,
    ensure_default_task_statuses,
    get_task_structure,
    list_available_assignees,
    list_saved_task_views,
    list_task_activity,
    list_task_comments,
    list_task_reminders,
    list_task_labels,
    move_task,
    delete_task_relation,
    reopen_task,
    replace_task_assignees,
    replace_task_labels,
    soft_delete_task,
    update_saved_task_view,
    update_task,
    update_task_comment,
    update_task_label,
)

router = APIRouter(tags=["وظایف"])


def _format_label(label: Any) -> dict[str, Any]:
    return {
        "id": label.id,
        "business_id": label.business_id,
        "name": label.name,
        "color": label.color,
        "description": label.description,
        "created_at": label.created_at,
        "updated_at": label.updated_at,
    }


def _format_saved_view(view: Any) -> dict[str, Any]:
    return {
        "id": view.id,
        "business_id": view.business_id,
        "user_id": view.user_id,
        "project_id": view.project_id,
        "name": view.name,
        "view_type": view.view_type,
        "filters": view.filters_json or {},
        "sort": view.sort_json or {},
        "is_shared": view.is_shared,
        "created_at": view.created_at,
        "updated_at": view.updated_at,
    }


def _format_status(status: TaskStatus) -> dict[str, Any]:
    return {
        "id": status.id,
        "business_id": status.business_id,
        "key": status.key,
        "name": status.name,
        "category": status.category,
        "color": status.color,
        "sort_order": status.sort_order,
        "is_default": status.is_default,
        "is_closed": status.is_closed,
    }


def _display_user_name(user: Any) -> str | None:
    if user is None:
        return None
    name = f"{user.first_name or ''} {user.last_name or ''}".strip()
    return name or user.email or user.mobile or f"User {user.id}"


def _format_reminder(reminder: Any) -> dict[str, Any]:
    return {
        "id": reminder.id,
        "task_id": reminder.task_id,
        "user_id": reminder.user_id,
        "remind_at": reminder.remind_at,
        "relative_to": reminder.relative_to,
        "offset_minutes": reminder.offset_minutes,
        "sent_at": reminder.sent_at,
        "created_at": reminder.created_at,
    }


def _format_comment(comment: Any) -> dict[str, Any]:
    return {
        "id": comment.id,
        "task_id": comment.task_id,
        "author_user_id": comment.author_user_id,
        "author_name": _display_user_name(comment.author),
        "body": comment.body,
        "created_at": comment.created_at,
        "updated_at": comment.updated_at,
    }


def _format_activity(event: Any) -> dict[str, Any]:
    return {
        "id": event.id,
        "task_id": event.task_id,
        "actor_user_id": event.actor_user_id,
        "actor_name": _display_user_name(event.actor),
        "event_type": event.event_type,
        "event_data": event.event_data or {},
        "created_at": event.created_at,
    }


def _format_task_brief(task: Task | None) -> dict[str, Any] | None:
    if task is None:
        return None
    return {
        "id": task.id,
        "business_id": task.business_id,
        "project_id": task.project_id,
        "parent_task_id": task.parent_task_id,
        "status_id": task.status_id,
        "status_name": task.status.name if task.status else None,
        "title": task.title,
        "priority": task.priority,
        "completed_at": task.completed_at,
    }


def _format_task(task: Task, db: Session, request: Request) -> dict[str, Any]:
    repo = TaskRepository(db)
    labels = [
        {
            "id": row.label.id,
            "name": row.label.name,
            "color": row.label.color,
            "description": row.label.description,
        }
        for row in repo.label_rows(task.id)
        if row.label is not None
    ]
    assignees = []
    for row in repo.assignee_rows(task.id):
        user = row.user
        name = ""
        if user:
            name = f"{user.first_name or ''} {user.last_name or ''}".strip()
        assignees.append(
            {
                "user_id": row.user_id,
                "name": name or (user.email if user else None) or f"User {row.user_id}",
                "assigned_at": row.assigned_at,
            }
        )

    data = {
        "id": task.id,
        "business_id": task.business_id,
        "project_id": task.project_id,
        "project_name": task.project.name if task.project else None,
        "parent_task_id": task.parent_task_id,
        "status_id": task.status_id,
        "status": _format_status(task.status) if task.status else None,
        "title": task.title,
        "description": task.description,
        "priority": task.priority,
        "sort_order": float(task.sort_order or 0),
        "start_at": task.start_at,
        "due_at": task.due_at,
        "completed_at": task.completed_at,
        "estimated_minutes": task.estimated_minutes,
        "recurrence_rule": task.recurrence_rule,
        "recurrence_timezone": task.recurrence_timezone,
        "recurrence_end_at": task.recurrence_end_at,
        "assignees": assignees,
        "labels": labels,
        "created_by_user_id": task.created_by_user_id,
        "created_at": task.created_at,
        "updated_at": task.updated_at,
        "archived_at": task.archived_at,
        "is_completed": task.completed_at is not None,
    }
    return format_datetime_fields(data, request, business_id=task.business_id)


@router.get("/businesses/{business_id}/task-labels")
@require_business_access("business_id")
async def list_task_labels_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    items = list_task_labels(db, business_id)
    return success_response(
        data=format_datetime_fields({"items": [_format_label(item) for item in items]}, request, business_id=business_id),
        request=request,
        message="TASK_LABELS_FETCHED",
    )


@router.post("/businesses/{business_id}/task-labels")
@require_business_access("business_id")
async def create_task_label_endpoint(
    request: Request,
    data: TaskLabelCreateRequest,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    label = create_task_label(db, business_id, data.name, data.color, data.description)
    return success_response(
        data=format_datetime_fields({"label": _format_label(label)}, request, business_id=business_id),
        request=request,
        message="TASK_LABEL_CREATED",
    )


@router.patch("/businesses/{business_id}/task-labels/{label_id}")
@require_business_access("business_id")
async def update_task_label_endpoint(
    request: Request,
    data: TaskLabelUpdateRequest,
    business_id: int = Path(..., gt=0),
    label_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    label = update_task_label(db, business_id, label_id, data.dict(exclude_unset=True))
    return success_response(
        data=format_datetime_fields({"label": _format_label(label)}, request, business_id=business_id),
        request=request,
        message="TASK_LABEL_UPDATED",
    )


@router.delete("/businesses/{business_id}/task-labels/{label_id}")
@require_business_access("business_id")
async def delete_task_label_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    label_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    delete_task_label(db, business_id, label_id)
    return success_response(data={"id": label_id}, request=request, message="TASK_LABEL_DELETED")


@router.get("/businesses/{business_id}/task-views")
@require_business_access("business_id")
async def list_task_views_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    items = list_saved_task_views(db, business_id, ctx.get_user_id())
    return success_response(
        data=format_datetime_fields({"items": [_format_saved_view(item) for item in items]}, request, business_id=business_id),
        request=request,
        message="TASK_VIEWS_FETCHED",
    )


@router.post("/businesses/{business_id}/task-views")
@require_business_access("business_id")
async def create_task_view_endpoint(
    request: Request,
    data: TaskSavedViewCreateRequest,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    view = create_saved_task_view(db, business_id, ctx.get_user_id(), data.dict())
    return success_response(
        data=format_datetime_fields({"view": _format_saved_view(view)}, request, business_id=business_id),
        request=request,
        message="TASK_VIEW_CREATED",
    )


@router.patch("/businesses/{business_id}/task-views/{view_id}")
@require_business_access("business_id")
async def update_task_view_endpoint(
    request: Request,
    data: TaskSavedViewUpdateRequest,
    business_id: int = Path(..., gt=0),
    view_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    view = update_saved_task_view(db, business_id, ctx.get_user_id(), view_id, data.dict(exclude_unset=True))
    return success_response(
        data=format_datetime_fields({"view": _format_saved_view(view)}, request, business_id=business_id),
        request=request,
        message="TASK_VIEW_UPDATED",
    )


@router.delete("/businesses/{business_id}/task-views/{view_id}")
@require_business_access("business_id")
async def delete_task_view_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    view_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    delete_saved_task_view(db, business_id, ctx.get_user_id(), view_id)
    return success_response(data={"id": view_id}, request=request, message="TASK_VIEW_DELETED")


@router.get("/businesses/{business_id}/task-statuses")
@require_business_access("business_id")
async def list_task_statuses(
    request: Request,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    statuses = ensure_default_task_statuses(db, business_id)
    return success_response(
        data={"items": [_format_status(item) for item in statuses]},
        request=request,
        message="TASK_STATUSES_FETCHED",
    )


@router.get("/businesses/{business_id}/task-assignees")
@require_business_access("business_id")
async def list_task_assignees(
    request: Request,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    return success_response(
        data={"users": list_available_assignees(db, business_id)},
        request=request,
        message="TASK_ASSIGNEES_FETCHED",
    )


@router.get("/businesses/{business_id}/tasks")
@require_business_access("business_id")
async def list_tasks(
    request: Request,
    business_id: int = Path(..., gt=0),
    search: Optional[str] = Query(None),
    project_id: Optional[int] = Query(None, gt=0),
    status_id: Optional[int] = Query(None, gt=0),
    assignee_user_id: Optional[int] = Query(None, gt=0),
    priority: Optional[str] = Query(None),
    label_id: Optional[int] = Query(None, gt=0),
    created_by_user_id: Optional[int] = Query(None, gt=0),
    due_from: Optional[datetime] = Query(None),
    due_to: Optional[datetime] = Query(None),
    completed: Optional[bool] = Query(None),
    sort_by: Optional[str] = Query(None),
    sort_dir: str = Query("asc", pattern="^(asc|desc)$"),
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    ensure_default_task_statuses(db, business_id)
    repo = TaskRepository(db)
    items, total = repo.list_tasks(
        business_id,
        search=search,
        project_id=project_id,
        status_id=status_id,
        assignee_user_id=assignee_user_id,
        priority=priority,
        label_id=label_id,
        created_by_user_id=created_by_user_id,
        due_from=due_from,
        due_to=due_to,
        completed=completed,
        sort_by=sort_by,
        sort_dir=sort_dir,
        skip=(page - 1) * limit,
        limit=limit,
    )
    return success_response(
        data={
            "items": [_format_task(item, db, request) for item in items],
            "total": total,
            "page": page,
            "limit": limit,
            "pages": (total + limit - 1) // limit if total else 0,
        },
        request=request,
        message="TASKS_FETCHED",
    )


@router.post("/businesses/{business_id}/tasks")
@require_business_access("business_id")
async def create_task_endpoint(
    request: Request,
    data: TaskCreateRequest,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    task = create_task(
        db,
        business_id,
        ctx.get_user_id(),
        data.dict(),
    )
    return success_response(
        data={"task": _format_task(task, db, request)},
        request=request,
        message="TASK_CREATED",
    )


@router.get("/businesses/{business_id}/tasks/{task_id}")
@require_business_access("business_id")
async def get_task_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    task = TaskRepository(db).get_by_id(task_id, business_id)
    if not task:
        raise ApiError("TASK_NOT_FOUND", "Task not found", http_status=404)
    return success_response(
        data={"task": _format_task(task, db, request)},
        request=request,
        message="TASK_FETCHED",
    )


@router.get("/businesses/{business_id}/tasks/{task_id}/reminders")
@require_business_access("business_id")
async def list_task_reminders_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    items = list_task_reminders(db, business_id, task_id)
    return success_response(
        data=format_datetime_fields(
            {"items": [_format_reminder(item) for item in items]},
            request,
            business_id=business_id,
        ),
        request=request,
        message="TASK_REMINDERS_FETCHED",
    )


@router.post("/businesses/{business_id}/tasks/{task_id}/reminders")
@require_business_access("business_id")
async def create_task_reminder_endpoint(
    request: Request,
    data: TaskReminderCreateRequest,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    reminder = create_task_reminder(
        db,
        business_id,
        task_id,
        ctx.get_user_id(),
        data.dict(),
    )
    return success_response(
        data=format_datetime_fields(
            {"reminder": _format_reminder(reminder)},
            request,
            business_id=business_id,
        ),
        request=request,
        message="TASK_REMINDER_CREATED",
    )


@router.delete("/businesses/{business_id}/tasks/{task_id}/reminders/{reminder_id}")
@require_business_access("business_id")
async def delete_task_reminder_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    reminder_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    delete_task_reminder(
        db,
        business_id,
        task_id,
        reminder_id,
        ctx.get_user_id(),
    )
    return success_response(
        data={"id": reminder_id},
        request=request,
        message="TASK_REMINDER_DELETED",
    )


@router.get("/businesses/{business_id}/tasks/{task_id}/comments")
@require_business_access("business_id")
async def list_task_comments_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    comments = list_task_comments(db, business_id, task_id)
    return success_response(
        data=format_datetime_fields(
            {"items": [_format_comment(item) for item in comments]},
            request,
            business_id=business_id,
        ),
        request=request,
        message="TASK_COMMENTS_FETCHED",
    )


@router.post("/businesses/{business_id}/tasks/{task_id}/comments")
@require_business_access("business_id")
async def add_task_comment_endpoint(
    request: Request,
    data: TaskCommentCreateRequest,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    comment = add_task_comment(
        db,
        business_id,
        task_id,
        ctx.get_user_id(),
        data.body,
    )
    return success_response(
        data=format_datetime_fields(
            {"comment": _format_comment(comment)},
            request,
            business_id=business_id,
        ),
        request=request,
        message="TASK_COMMENT_CREATED",
    )


@router.patch("/businesses/{business_id}/tasks/{task_id}/comments/{comment_id}")
@require_business_access("business_id")
async def update_task_comment_endpoint(
    request: Request,
    data: TaskCommentUpdateRequest,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    comment_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    comment = update_task_comment(
        db,
        business_id,
        task_id,
        comment_id,
        ctx.get_user_id(),
        data.body,
    )
    return success_response(
        data=format_datetime_fields(
            {"comment": _format_comment(comment)},
            request,
            business_id=business_id,
        ),
        request=request,
        message="TASK_COMMENT_UPDATED",
    )


@router.delete("/businesses/{business_id}/tasks/{task_id}/comments/{comment_id}")
@require_business_access("business_id")
async def delete_task_comment_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    comment_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    delete_task_comment(
        db,
        business_id,
        task_id,
        comment_id,
        ctx.get_user_id(),
    )
    return success_response(
        data={"id": comment_id},
        request=request,
        message="TASK_COMMENT_DELETED",
    )


@router.get("/businesses/{business_id}/tasks/{task_id}/activity")
@require_business_access("business_id")
async def list_task_activity_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    limit: int = Query(100, ge=1, le=200),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    events = list_task_activity(
        db,
        business_id,
        task_id,
        limit=limit,
    )
    return success_response(
        data=format_datetime_fields(
            {"items": [_format_activity(item) for item in events]},
            request,
            business_id=business_id,
        ),
        request=request,
        message="TASK_ACTIVITY_FETCHED",
    )


@router.get("/businesses/{business_id}/tasks/{task_id}/structure")
@require_business_access("business_id")
async def get_task_structure_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    structure = get_task_structure(db, business_id, task_id)
    task = structure["task"]
    relations = []
    for relation in structure["relations"]:
        outgoing = relation.task_id == task.id
        other_id = (
            relation.related_task_id if outgoing else relation.task_id
        )
        other = TaskRepository(db).get_by_id(other_id, business_id)
        relations.append(
            {
                "id": relation.id,
                "relation_type": relation.relation_type,
                "direction": "outgoing" if outgoing else "incoming",
                "task": _format_task_brief(other),
                "created_at": relation.created_at,
            }
        )
    data = {
        "parent": _format_task_brief(structure["parent"]),
        "subtasks": [
            _format_task_brief(item) for item in structure["subtasks"]
        ],
        "relations": relations,
    }
    return success_response(
        data=format_datetime_fields(data, request, business_id=business_id),
        request=request,
        message="TASK_STRUCTURE_FETCHED",
    )


@router.post("/businesses/{business_id}/tasks/{task_id}/subtasks")
@require_business_access("business_id")
async def create_subtask_endpoint(
    request: Request,
    data: TaskSubtaskCreateRequest,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    task = create_subtask(
        db,
        business_id,
        task_id,
        ctx.get_user_id(),
        data.dict(),
    )
    return success_response(
        data={"task": _format_task(task, db, request)},
        request=request,
        message="SUBTASK_CREATED",
    )


@router.post("/businesses/{business_id}/tasks/{task_id}/relations")
@require_business_access("business_id")
async def add_task_relation_endpoint(
    request: Request,
    data: TaskRelationCreateRequest,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    relation = add_task_relation(
        db,
        business_id,
        task_id,
        ctx.get_user_id(),
        data.related_task_id,
        data.relation_type,
    )
    return success_response(
        data={"relation_id": relation.id},
        request=request,
        message="TASK_RELATION_CREATED",
    )


@router.delete("/businesses/{business_id}/tasks/{task_id}/relations/{relation_id}")
@require_business_access("business_id")
async def delete_task_relation_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    relation_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    delete_task_relation(
        db,
        business_id,
        task_id,
        relation_id,
        ctx.get_user_id(),
    )
    return success_response(
        data={"id": relation_id},
        request=request,
        message="TASK_RELATION_DELETED",
    )


@router.patch("/businesses/{business_id}/tasks/{task_id}")
@require_business_access("business_id")
async def update_task_endpoint(
    request: Request,
    data: TaskUpdateRequest,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    task = update_task(
        db,
        business_id,
        task_id,
        ctx.get_user_id(),
        data.dict(exclude_unset=True),
    )
    return success_response(
        data={"task": _format_task(task, db, request)},
        request=request,
        message="TASK_UPDATED",
    )


@router.delete("/businesses/{business_id}/tasks/{task_id}")
@require_business_access("business_id")
async def delete_task_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    soft_delete_task(db, business_id, task_id, ctx.get_user_id())
    return success_response(
        data={"id": task_id},
        request=request,
        message="TASK_DELETED",
    )


@router.put("/businesses/{business_id}/tasks/{task_id}/labels")
@require_business_access("business_id")
async def replace_task_labels_endpoint(
    request: Request,
    data: TaskLabelsAssignRequest,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    task = TaskRepository(db).get_by_id(task_id, business_id)
    if not task:
        raise ApiError("TASK_NOT_FOUND", "Task not found", http_status=404)
    replace_task_labels(
        db,
        task=task,
        label_ids=data.label_ids,
        actor_user_id=ctx.get_user_id(),
        commit=True,
    )
    task = TaskRepository(db).get_by_id(task_id, business_id) or task
    return success_response(
        data={"task": _format_task(task, db, request)},
        request=request,
        message="TASK_LABELS_UPDATED",
    )


@router.post("/businesses/{business_id}/tasks/{task_id}/move")
@require_business_access("business_id")
async def move_task_endpoint(
    request: Request,
    data: TaskMoveRequest,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    task = move_task(
        db,
        business_id,
        task_id,
        ctx.get_user_id(),
        data.target_status_id,
        data.target_index,
    )
    return success_response(
        data={"task": _format_task(task, db, request)},
        request=request,
        message="TASK_MOVED",
    )


@router.post("/businesses/{business_id}/tasks/{task_id}/complete")
@require_business_access("business_id")
async def complete_task_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    task = complete_task(db, business_id, task_id, ctx.get_user_id())
    return success_response(
        data={"task": _format_task(task, db, request)},
        request=request,
        message="TASK_COMPLETED",
    )


@router.post("/businesses/{business_id}/tasks/{task_id}/reopen")
@require_business_access("business_id")
async def reopen_task_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    task = reopen_task(db, business_id, task_id, ctx.get_user_id())
    return success_response(
        data={"task": _format_task(task, db, request)},
        request=request,
        message="TASK_REOPENED",
    )


@router.put("/businesses/{business_id}/tasks/{task_id}/assignees")
@require_business_access("business_id")
async def replace_task_assignees_endpoint(
    request: Request,
    data: TaskAssigneesRequest,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    task = TaskRepository(db).get_by_id(task_id, business_id)
    if not task:
        raise ApiError("TASK_NOT_FOUND", "Task not found", http_status=404)
    replace_task_assignees(
        db,
        task=task,
        assignee_user_ids=data.user_ids,
        actor_user_id=ctx.get_user_id(),
        commit=True,
    )
    task = TaskRepository(db).get_by_id(task_id, business_id) or task
    return success_response(
        data={"task": _format_task(task, db, request)},
        request=request,
        message="TASK_ASSIGNEES_UPDATED",
    )
