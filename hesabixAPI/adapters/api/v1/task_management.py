from __future__ import annotations

from typing import Any, Optional

from fastapi import APIRouter, Depends, Path, Query, Request
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.task_management import (
    TaskAssigneesRequest,
    TaskCommentCreateRequest,
    TaskCommentUpdateRequest,
    TaskCreateRequest,
    TaskMoveRequest,
    TaskRelationCreateRequest,
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
    complete_task,
    create_subtask,
    create_task,
    delete_task_comment,
    ensure_default_task_statuses,
    get_task_structure,
    list_available_assignees,
    list_task_activity,
    list_task_comments,
    move_task,
    delete_task_relation,
    reopen_task,
    replace_task_assignees,
    soft_delete_task,
    update_task,
    update_task_comment,
)

router = APIRouter(tags=["وظایف"])


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
        "assignees": assignees,
        "created_by_user_id": task.created_by_user_id,
        "created_at": task.created_at,
        "updated_at": task.updated_at,
        "archived_at": task.archived_at,
        "is_completed": task.completed_at is not None,
    }
    return format_datetime_fields(data, request, business_id=task.business_id)


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
    completed: Optional[bool] = Query(None),
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
        completed=completed,
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
