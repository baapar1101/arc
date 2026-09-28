from __future__ import annotations

from datetime import datetime
from typing import Any, Optional

from fastapi import APIRouter, Depends, File, Path, Query, Request, Response, UploadFile
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.task_management import (
    TaskAssigneesRequest,
    TaskCommentCreateRequest,
    TaskCommentUpdateRequest,
    TaskCreateRequest,
    TaskCyclesAssignRequest,
    TaskEntityLinkCreateRequest,
    TaskLabelCreateRequest,
    TaskLabelUpdateRequest,
    TaskLabelsAssignRequest,
    TaskMoveRequest,
    TaskProjectTemplateCreateRequest,
    TaskProjectTemplateInstantiateRequest,
    TaskProjectTemplateSnapshotRequest,
    TaskProjectTemplateUpdateRequest,
    TaskRelationCreateRequest,
    TaskReminderCreateRequest,
    TaskSavedViewCreateRequest,
    TaskSavedViewUpdateRequest,
    TaskSubtaskCreateRequest,
    TaskTimeEntryCreateRequest,
    TaskTimeEntryUpdateRequest,
    TaskTimerStartRequest,
    TaskUpdateRequest,
)
from adapters.db.models.task_management import Task, TaskStatus
from adapters.db.repositories.task_repository import TaskRepository
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_access
from app.core.task_project_permissions import (
    business_project_action,
    require_project_capability,
    require_task_capability,
    task_route_guard_dep,
    task_visibility_scope,
)
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.services.task_attachment_service import TaskAttachmentService
from app.services.task_dashboard_service import get_task_dashboard
from app.services.task_template_service import (
    create_project_task_template,
    delete_project_task_template,
    instantiate_project_task_template,
    list_project_task_templates,
    snapshot_project_as_template,
    update_project_task_template,
)
from app.services.task_management_service import (
    add_task_comment,
    add_task_relation,
    add_task_entity_link,
    create_saved_task_view,
    create_task_label,
    complete_task,
    create_task_reminder,
    create_subtask,
    create_task,
    delete_saved_task_view,
    delete_task_comment,
    delete_task_entity_link,
    delete_task_reminder,
    delete_task_label,
    ensure_default_task_statuses,
    get_active_time_entry,
    get_task_structure,
    list_available_assignees,
    list_saved_task_views,
    list_task_activity,
    list_task_entity_links,
    list_task_entity_types,
    list_task_comments,
    list_task_cycles,
    list_task_reminders,
    list_task_labels,
    list_time_entries,
    list_entity_linked_tasks,
    move_task,
    search_task_entity_targets,
    delete_task_relation,
    reopen_task,
    replace_task_assignees,
    replace_task_cycles,
    replace_task_labels,
    soft_delete_task,
    start_task_timer,
    stop_active_timer,
    create_manual_time_entry,
    update_time_entry,
    delete_time_entry,
    update_saved_task_view,
    update_task,
    update_task_comment,
    update_task_label,
)

router = APIRouter(tags=["وظایف"], dependencies=[Depends(task_route_guard_dep)])


def _format_task_template(row: Any) -> dict[str, Any]:
    return {
        "id": row.id,
        "business_id": row.business_id,
        "name": row.name,
        "description": row.description,
        "project_defaults": row.project_defaults_json or {},
        "tasks": row.tasks_json or [],
        "task_count": len(row.tasks_json or []),
        "is_active": row.is_active,
        "created_by_user_id": row.created_by_user_id,
        "created_at": row.created_at,
        "updated_at": row.updated_at,
    }


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


def _format_time_entry(entry: Any) -> dict[str, Any]:
    user = entry.user
    task = entry.task
    return {
        "id": entry.id,
        "business_id": entry.business_id,
        "task_id": entry.task_id,
        "task_title": task.title if task else None,
        "project_id": task.project_id if task else None,
        "user_id": entry.user_id,
        "user_name": _display_user_name(user),
        "started_at": entry.started_at,
        "ended_at": entry.ended_at,
        "duration_seconds": entry.duration_seconds,
        "description": entry.description,
        "billable": entry.billable,
        "created_at": entry.created_at,
        "updated_at": entry.updated_at,
        "is_active": entry.ended_at is None,
    }


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
        "milestone_id": task.milestone_id,
        "milestone_name": task.milestone.title if task.milestone else None,
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


@router.get("/businesses/{business_id}/task-templates")
@require_business_access("business_id")
async def list_task_templates_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    include_inactive: bool = Query(False),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    if not business_project_action(ctx, db, business_id, "view"):
        raise ApiError(
            "PROJECT_PERMISSION_DENIED",
            "Missing project capability: view",
            http_status=403,
        )
    items = list_project_task_templates(
        db,
        business_id,
        include_inactive=include_inactive,
    )
    return success_response(
        data=format_datetime_fields(
            {"items": [_format_task_template(item) for item in items]},
            request,
            business_id=business_id,
        ),
        request=request,
        message="TASK_TEMPLATES_FETCHED",
    )


@router.post("/businesses/{business_id}/task-templates")
@require_business_access("business_id")
async def create_task_template_endpoint(
    request: Request,
    data: TaskProjectTemplateCreateRequest,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    if not business_project_action(ctx, db, business_id, "project_create"):
        raise ApiError(
            "PROJECT_PERMISSION_DENIED",
            "Missing project capability: project_create",
            http_status=403,
        )
    row = create_project_task_template(
        db,
        business_id,
        ctx.get_user_id(),
        data.dict(),
    )
    return success_response(
        data={"template": _format_task_template(row)},
        request=request,
        message="TASK_TEMPLATE_CREATED",
    )


@router.patch("/businesses/{business_id}/task-templates/{template_id}")
@require_business_access("business_id")
async def update_task_template_endpoint(
    request: Request,
    data: TaskProjectTemplateUpdateRequest,
    business_id: int = Path(..., gt=0),
    template_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    if not business_project_action(ctx, db, business_id, "project_edit"):
        raise ApiError(
            "PROJECT_PERMISSION_DENIED",
            "Missing project capability: project_edit",
            http_status=403,
        )
    row = update_project_task_template(
        db,
        business_id,
        template_id,
        data.dict(exclude_unset=True),
    )
    return success_response(
        data={"template": _format_task_template(row)},
        request=request,
        message="TASK_TEMPLATE_UPDATED",
    )


@router.delete("/businesses/{business_id}/task-templates/{template_id}")
@require_business_access("business_id")
async def delete_task_template_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    template_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    if not business_project_action(ctx, db, business_id, "project_delete"):
        raise ApiError(
            "PROJECT_PERMISSION_DENIED",
            "Missing project capability: project_delete",
            http_status=403,
        )
    delete_project_task_template(db, business_id, template_id)
    return success_response(
        data={"id": template_id},
        request=request,
        message="TASK_TEMPLATE_DELETED",
    )


@router.post(
    "/businesses/{business_id}/projects/{project_id}/task-template-snapshot"
)
@require_business_access("business_id")
async def snapshot_task_template_endpoint(
    request: Request,
    data: TaskProjectTemplateSnapshotRequest,
    business_id: int = Path(..., gt=0),
    project_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    require_project_capability(
        ctx,
        db,
        business_id,
        project_id,
        "project_edit",
    )
    row = snapshot_project_as_template(
        db,
        business_id,
        project_id,
        ctx.get_user_id(),
        name=data.name,
        description=data.description,
    )
    return success_response(
        data={"template": _format_task_template(row)},
        request=request,
        message="TASK_TEMPLATE_SNAPSHOT_CREATED",
    )


@router.post(
    "/businesses/{business_id}/task-templates/{template_id}/instantiate"
)
@require_business_access("business_id")
async def instantiate_task_template_endpoint(
    request: Request,
    data: TaskProjectTemplateInstantiateRequest,
    business_id: int = Path(..., gt=0),
    template_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    if data.project_id is not None:
        require_project_capability(
            ctx,
            db,
            business_id,
            data.project_id,
            "task_create",
        )
    elif not business_project_action(
        ctx,
        db,
        business_id,
        "project_create",
    ):
        raise ApiError(
            "PROJECT_PERMISSION_DENIED",
            "Missing project capability: project_create",
            http_status=403,
        )
    result = instantiate_project_task_template(
        db,
        business_id,
        template_id,
        ctx.get_user_id(),
        data.dict(exclude_none=True),
    )
    return success_response(
        data=result,
        request=request,
        message="TASK_TEMPLATE_INSTANTIATED",
    )


@router.get("/businesses/{business_id}/task-dashboard")
@require_business_access("business_id")
async def get_task_dashboard_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    data = get_task_dashboard(db, business_id, ctx)
    return success_response(
        data=format_datetime_fields(
            data,
            request,
            business_id=business_id,
        ),
        request=request,
        message="TASK_DASHBOARD_FETCHED",
    )


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
    if project_id is not None:
        require_project_capability(
            ctx,
            db,
            business_id,
            project_id,
            "view",
        )
    visible_project_ids, visible_user_id = task_visibility_scope(
        ctx,
        db,
        business_id,
    )
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
        visible_project_ids=visible_project_ids,
        visible_user_id=visible_user_id,
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
    if data.project_id is not None:
        require_project_capability(
            ctx,
            db,
            business_id,
            data.project_id,
            "task_create",
        )
    elif not business_project_action(
        ctx,
        db,
        business_id,
        "task_create",
    ):
        raise ApiError(
            "TASK_PERMISSION_DENIED",
            "Missing task capability: task_create",
            http_status=403,
        )
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


@router.get("/businesses/{business_id}/time-entries")
@require_business_access("business_id")
async def list_time_entries_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    task_id: Optional[int] = Query(None, gt=0),
    project_id: Optional[int] = Query(None, gt=0),
    user_id: Optional[int] = Query(None, gt=0),
    limit: int = Query(200, ge=1, le=500),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    requested_user_id = user_id
    effective_user_id = user_id
    if project_id is not None:
        can_team = True
        try:
            require_project_capability(
                ctx,
                db,
                business_id,
                project_id,
                "time_view_team",
            )
        except ApiError:
            can_team = False
        if not can_team:
            if requested_user_id is not None and requested_user_id != ctx.get_user_id():
                raise ApiError(
                    "TASK_TIME_PERMISSION_DENIED",
                    "You can only view your own time entries",
                    http_status=403,
                )
            effective_user_id = ctx.get_user_id()
    elif not business_project_action(ctx, db, business_id, "time_view_team"):
        if requested_user_id is not None and requested_user_id != ctx.get_user_id():
            raise ApiError(
                "TASK_TIME_PERMISSION_DENIED",
                "You can only view your own time entries",
                http_status=403,
            )
        effective_user_id = ctx.get_user_id()

    items = list_time_entries(
        db,
        business_id,
        task_id=task_id,
        project_id=project_id,
        user_id=effective_user_id,
        limit=limit,
    )
    total_seconds = sum(
        int(item.duration_seconds or 0)
        for item in items
        if item.ended_at is not None
    )
    return success_response(
        data=format_datetime_fields(
            {
                "items": [_format_time_entry(item) for item in items],
                "total_seconds": total_seconds,
            },
            request,
            business_id=business_id,
        ),
        request=request,
        message="TASK_TIME_ENTRIES_FETCHED",
    )


@router.get("/businesses/{business_id}/timer/active")
@require_business_access("business_id")
async def get_active_timer_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    entry = get_active_time_entry(db, business_id, ctx.get_user_id())
    return success_response(
        data=format_datetime_fields(
            {"entry": _format_time_entry(entry) if entry else None},
            request,
            business_id=business_id,
        ),
        request=request,
        message="TASK_ACTIVE_TIMER_FETCHED",
    )


@router.post("/businesses/{business_id}/tasks/{task_id}/timer/start")
@require_business_access("business_id")
async def start_task_timer_endpoint(
    request: Request,
    data: TaskTimerStartRequest,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    entry = start_task_timer(
        db,
        business_id,
        task_id,
        ctx.get_user_id(),
        description=data.description,
        billable=data.billable,
    )
    return success_response(
        data=format_datetime_fields(
            {"entry": _format_time_entry(entry)},
            request,
            business_id=business_id,
        ),
        request=request,
        message="TASK_TIMER_STARTED",
    )


@router.post("/businesses/{business_id}/timer/stop")
@require_business_access("business_id")
async def stop_task_timer_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    entry = stop_active_timer(db, business_id, ctx.get_user_id())
    return success_response(
        data=format_datetime_fields(
            {"entry": _format_time_entry(entry)},
            request,
            business_id=business_id,
        ),
        request=request,
        message="TASK_TIMER_STOPPED",
    )


@router.post("/businesses/{business_id}/tasks/{task_id}/time-entries")
@require_business_access("business_id")
async def create_time_entry_endpoint(
    request: Request,
    data: TaskTimeEntryCreateRequest,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    entry = create_manual_time_entry(
        db,
        business_id,
        task_id,
        ctx.get_user_id(),
        data.dict(),
    )
    return success_response(
        data=format_datetime_fields(
            {"entry": _format_time_entry(entry)},
            request,
            business_id=business_id,
        ),
        request=request,
        message="TASK_TIME_ENTRY_CREATED",
    )


@router.patch("/businesses/{business_id}/time-entries/{entry_id}")
@require_business_access("business_id")
async def update_time_entry_endpoint(
    request: Request,
    data: TaskTimeEntryUpdateRequest,
    business_id: int = Path(..., gt=0),
    entry_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    entry = update_time_entry(
        db,
        business_id,
        entry_id,
        ctx.get_user_id(),
        data.dict(exclude_unset=True),
    )
    return success_response(
        data=format_datetime_fields(
            {"entry": _format_time_entry(entry)},
            request,
            business_id=business_id,
        ),
        request=request,
        message="TASK_TIME_ENTRY_UPDATED",
    )


@router.delete("/businesses/{business_id}/time-entries/{entry_id}")
@require_business_access("business_id")
async def delete_time_entry_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    entry_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    delete_time_entry(db, business_id, entry_id, ctx.get_user_id())
    return success_response(
        data={"id": entry_id},
        request=request,
        message="TASK_TIME_ENTRY_DELETED",
    )


@router.get("/businesses/{business_id}/tasks/{task_id}/cycles")
@require_business_access("business_id")
async def list_task_cycles_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    items = list_task_cycles(db, business_id, task_id)
    return success_response(
        data=format_datetime_fields(
            {
                "items": [
                    {
                        "id": item.id,
                        "project_id": item.project_id,
                        "name": item.name,
                        "goal": item.goal,
                        "start_at": item.start_at,
                        "end_at": item.end_at,
                        "status": item.status,
                    }
                    for item in items
                ]
            },
            request,
            business_id=business_id,
        ),
        request=request,
        message="TASK_CYCLES_FETCHED",
    )


@router.put("/businesses/{business_id}/tasks/{task_id}/cycles")
@require_business_access("business_id")
async def replace_task_cycles_endpoint(
    request: Request,
    data: TaskCyclesAssignRequest,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    items = replace_task_cycles(
        db,
        business_id,
        task_id,
        ctx.get_user_id(),
        data.cycle_ids,
    )
    return success_response(
        data=format_datetime_fields(
            {
                "items": [
                    {
                        "id": item.id,
                        "project_id": item.project_id,
                        "name": item.name,
                        "goal": item.goal,
                        "start_at": item.start_at,
                        "end_at": item.end_at,
                        "status": item.status,
                    }
                    for item in items
                ]
            },
            request,
            business_id=business_id,
        ),
        request=request,
        message="TASK_CYCLES_UPDATED",
    )


@router.get("/businesses/{business_id}/task-link-entity-types")
@require_business_access("business_id")
async def list_task_link_entity_types_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    ctx: AuthContext = Depends(get_current_user),
):
    del business_id, ctx
    return success_response(
        data={"items": list_task_entity_types()},
        request=request,
        message="TASK_ENTITY_TYPES_FETCHED",
    )


@router.get("/businesses/{business_id}/task-link-targets")
@require_business_access("business_id")
async def search_task_link_targets_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    entity_type: str = Query(..., min_length=1, max_length=50),
    search: Optional[str] = Query(None),
    limit: int = Query(25, ge=1, le=50),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    items = search_task_entity_targets(
        db,
        business_id,
        entity_type,
        search=search,
        limit=limit,
    )
    return success_response(
        data={"items": items},
        request=request,
        message="TASK_LINK_TARGETS_FETCHED",
    )


@router.get("/businesses/{business_id}/tasks/{task_id}/entity-links")
@require_business_access("business_id")
async def list_task_entity_links_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    items = list_task_entity_links(db, business_id, task_id)
    return success_response(
        data=format_datetime_fields(
            {"items": items},
            request,
            business_id=business_id,
        ),
        request=request,
        message="TASK_ENTITY_LINKS_FETCHED",
    )


@router.post("/businesses/{business_id}/tasks/{task_id}/entity-links")
@require_business_access("business_id")
async def add_task_entity_link_endpoint(
    request: Request,
    data: TaskEntityLinkCreateRequest,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    row = add_task_entity_link(
        db,
        business_id,
        task_id,
        ctx.get_user_id(),
        entity_type=data.entity_type,
        entity_id=data.entity_id,
        relationship_type=data.relationship_type,
    )
    items = list_task_entity_links(db, business_id, task_id)
    item = next((value for value in items if value["id"] == row.id), None)
    return success_response(
        data=format_datetime_fields(
            {"link": item},
            request,
            business_id=business_id,
        ),
        request=request,
        message="TASK_ENTITY_LINK_CREATED",
    )


@router.delete("/businesses/{business_id}/tasks/{task_id}/entity-links/{link_id}")
@require_business_access("business_id")
async def delete_task_entity_link_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    link_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    delete_task_entity_link(
        db,
        business_id,
        task_id,
        link_id,
        ctx.get_user_id(),
    )
    return success_response(
        data={"id": link_id},
        request=request,
        message="TASK_ENTITY_LINK_DELETED",
    )


@router.get("/businesses/{business_id}/entities/{entity_type}/{entity_id}/tasks")
@require_business_access("business_id")
async def list_entity_linked_tasks_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    entity_type: str = Path(..., min_length=1, max_length=50),
    entity_id: str = Path(..., min_length=1, max_length=64),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    tasks = list_entity_linked_tasks(
        db,
        business_id,
        entity_type,
        entity_id,
    )
    visible_tasks = []
    for task in tasks:
        try:
            require_task_capability(
                ctx,
                db,
                business_id,
                task.id,
                "view",
            )
            visible_tasks.append(task)
        except ApiError as exc:
            if exc.status_code != 403:
                raise
    return success_response(
        data={"items": [_format_task(task, db, request) for task in visible_tasks]},
        request=request,
        message="ENTITY_TASKS_FETCHED",
    )


@router.get("/businesses/{business_id}/tasks/{task_id}/attachments")
@require_business_access("business_id")
async def list_task_attachments_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    service = TaskAttachmentService(db)
    items = service.list(business_id, task_id)
    return success_response(
        data=format_datetime_fields(
            {"items": [service.to_dict(item) for item in items]},
            request,
            business_id=business_id,
        ),
        request=request,
        message="TASK_ATTACHMENTS_FETCHED",
    )


@router.post("/businesses/{business_id}/tasks/{task_id}/attachments")
@require_business_access("business_id")
async def upload_task_attachment_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    service = TaskAttachmentService(db)
    item = await service.upload(
        business_id=business_id,
        task_id=task_id,
        user_id=ctx.get_user_id(),
        file=file,
    )
    return success_response(
        data=format_datetime_fields(
            {"attachment": service.to_dict(item)},
            request,
            business_id=business_id,
        ),
        request=request,
        message="TASK_ATTACHMENT_CREATED",
    )


@router.get("/businesses/{business_id}/tasks/{task_id}/attachments/{attachment_id}/download")
@require_business_access("business_id")
async def download_task_attachment_endpoint(
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    attachment_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    service = TaskAttachmentService(db)
    data = await service.download(business_id, task_id, attachment_id)
    return Response(
        content=data["content"],
        media_type=data["mime_type"],
        headers={
            "Content-Disposition": f'attachment; filename="{data["filename"]}"'
        },
    )


@router.delete("/businesses/{business_id}/tasks/{task_id}/attachments/{attachment_id}")
@require_business_access("business_id")
async def delete_task_attachment_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    task_id: int = Path(..., gt=0),
    attachment_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    service = TaskAttachmentService(db)
    await service.delete(
        business_id=business_id,
        task_id=task_id,
        attachment_id=attachment_id,
        actor_user_id=ctx.get_user_id(),
    )
    return success_response(
        data={"id": attachment_id},
        request=request,
        message="TASK_ATTACHMENT_DELETED",
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
