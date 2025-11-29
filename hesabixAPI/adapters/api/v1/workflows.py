"""
API endpoints برای مدیریت Workflow
"""

from typing import Any, Dict, List, Optional
from fastapi import APIRouter, Depends, Request, Body, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import select, and_, or_, func

from adapters.db.session import get_db
from adapters.db.models.workflow import (
    Workflow,
    WorkflowStatus,
    WorkflowExecution,
    WorkflowExecutionStatus,
    WorkflowLog,
)
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.responses import success_response, format_datetime_fields, ApiError
from app.services.workflow.workflow_engine import WorkflowEngine
from app.services.workflow.trigger_registry import TriggerRegistry
from app.services.workflow.action_registry import ActionRegistry
from adapters.api.v1.schemas import QueryInfo

router = APIRouter(tags=["workflows"])


@router.post(
    "/businesses/{business_id}/workflows/create",
    summary="ایجاد workflow جدید",
    description="ایجاد یک workflow جدید برای کسب‌وکار",
)
@require_business_access("business_id")
async def create_workflow(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("workflows", "add")),
):
    """ایجاد workflow جدید"""
    name = body.get("name")
    if not name:
        raise ApiError("WORKFLOW_NAME_REQUIRED", "نام workflow الزامی است")
    
    workflow_data = body.get("workflow_data", {})
    if not workflow_data:
        raise ApiError("WORKFLOW_DATA_REQUIRED", "داده‌های workflow الزامی است")
    
    workflow = Workflow(
        business_id=business_id,
        name=name,
        description=body.get("description"),
        status=WorkflowStatus(body.get("status", WorkflowStatus.DRAFT.value)),
        workflow_data=workflow_data,
        settings=body.get("settings"),
        created_by_user_id=ctx.get_user_id(),
    )
    
    db.add(workflow)
    db.commit()
    db.refresh(workflow)
    
    return success_response(
        data=format_datetime_fields(workflow.__dict__, request),
        request=request,
        message="WORKFLOW_CREATED",
    )


@router.post(
    "/businesses/{business_id}/workflows/list",
    summary="لیست workflowها",
    description="دریافت لیست workflowهای یک کسب‌وکار",
)
@require_business_access("business_id")
async def list_workflows(
    request: Request,
    business_id: int,
    query_info: QueryInfo = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """لیست workflowها"""
    stmt = select(Workflow).where(Workflow.business_id == business_id)
    
    # اعمال فیلترها
    if query_info.filters:
        for filter_item in query_info.filters:
            if filter_item.property == "status":
                stmt = stmt.where(Workflow.status == filter_item.value)
            elif filter_item.property == "name":
                stmt = stmt.where(Workflow.name.ilike(f"%{filter_item.value}%"))
    
    # مرتب‌سازی
    if query_info.sort_by:
        sort_desc = query_info.sort_desc
        if query_info.sort_by == "name":
            stmt = stmt.order_by(Workflow.name.desc() if sort_desc else Workflow.name.asc())
        elif query_info.sort_by == "created_at":
            stmt = stmt.order_by(Workflow.created_at.desc() if sort_desc else Workflow.created_at.asc())
        else:
            stmt = stmt.order_by(Workflow.created_at.desc())
    else:
        stmt = stmt.order_by(Workflow.created_at.desc())
    
    total_count = db.execute(
        stmt.with_only_columns(func.count()).order_by(None)
    ).scalar_one()
    
    skip = query_info.skip or 0
    take = query_info.take or 10
    stmt = stmt.offset(skip).limit(take)
    
    workflows = list(db.execute(stmt).scalars().all())
    
    page = (skip // take) + 1
    
    return success_response(
        data={
            "items": [format_datetime_fields(w.__dict__, request) for w in workflows],
            "total": total_count,
            "page": page,
            "page_size": take,
        },
        request=request,
        message="WORKFLOWS_LISTED",
    )


@router.get(
    "/businesses/{business_id}/workflows/{workflow_id}",
    summary="دریافت workflow",
    description="دریافت اطلاعات یک workflow",
)
@require_business_access("business_id")
async def get_workflow(
    request: Request,
    business_id: int,
    workflow_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """دریافت workflow"""
    workflow = db.get(Workflow, workflow_id)
    if not workflow or workflow.business_id != business_id:
        raise ApiError("WORKFLOW_NOT_FOUND", "Workflow یافت نشد")
    
    return success_response(
        data=format_datetime_fields(workflow.__dict__, request),
        request=request,
        message="WORKFLOW_RETRIEVED",
    )


@router.put(
    "/businesses/{business_id}/workflows/{workflow_id}/edit",
    summary="به‌روزرسانی workflow",
    description="به‌روزرسانی یک workflow",
)
@require_business_access("business_id")
async def update_workflow(
    request: Request,
    business_id: int,
    workflow_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("workflows", "edit")),
):
    """به‌روزرسانی workflow"""
    workflow = db.get(Workflow, workflow_id)
    if not workflow or workflow.business_id != business_id:
        raise ApiError("WORKFLOW_NOT_FOUND", "Workflow یافت نشد")
    
    if "name" in body:
        workflow.name = body["name"]
    if "description" in body:
        workflow.description = body["description"]
    if "status" in body:
        workflow.status = WorkflowStatus(body["status"])
    if "workflow_data" in body:
        workflow.workflow_data = body["workflow_data"]
    if "settings" in body:
        workflow.settings = body["settings"]
    
    db.commit()
    db.refresh(workflow)
    
    return success_response(
        data=format_datetime_fields(workflow.__dict__, request),
        request=request,
        message="WORKFLOW_UPDATED",
    )


@router.delete(
    "/businesses/{business_id}/workflows/{workflow_id}",
    summary="حذف workflow",
    description="حذف یک workflow",
)
@require_business_access("business_id")
async def delete_workflow(
    request: Request,
    business_id: int,
    workflow_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("workflows", "delete")),
):
    """حذف workflow"""
    workflow = db.get(Workflow, workflow_id)
    if not workflow or workflow.business_id != business_id:
        raise ApiError("WORKFLOW_NOT_FOUND", "Workflow یافت نشد")
    
    db.delete(workflow)
    db.commit()
    
    return success_response(
        data=None,
        request=request,
        message="WORKFLOW_DELETED",
    )


@router.post(
    "/businesses/{business_id}/workflows/{workflow_id}/execute",
    summary="اجرای workflow",
    description="اجرای دستی یک workflow",
)
@require_business_access("business_id")
async def execute_workflow(
    request: Request,
    business_id: int,
    workflow_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """اجرای workflow"""
    workflow = db.get(Workflow, workflow_id)
    if not workflow or workflow.business_id != business_id:
        raise ApiError("WORKFLOW_NOT_FOUND", "Workflow یافت نشد")
    
    if workflow.status != WorkflowStatus.ACTIVE:
        raise ApiError("WORKFLOW_NOT_ACTIVE", "Workflow فعال نیست")
    
    trigger_data = body.get("trigger_data", {})
    
    # اجرای workflow
    engine = WorkflowEngine(db, business_id, ctx.get_user_id())
    execution = engine.execute_workflow(workflow, trigger_data)
    
    return success_response(
        data=format_datetime_fields(execution.__dict__, request),
        request=request,
        message="WORKFLOW_EXECUTED",
    )


@router.get(
    "/businesses/{business_id}/workflows/{workflow_id}/executions",
    summary="لیست اجراهای workflow",
    description="دریافت لیست اجراهای یک workflow",
)
@require_business_access("business_id")
async def list_workflow_executions(
    request: Request,
    business_id: int,
    workflow_id: int,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """لیست اجراهای workflow"""
    workflow = db.get(Workflow, workflow_id)
    if not workflow or workflow.business_id != business_id:
        raise ApiError("WORKFLOW_NOT_FOUND", "Workflow یافت نشد")
    
    stmt = select(WorkflowExecution).where(WorkflowExecution.workflow_id == workflow_id)
    stmt = stmt.order_by(WorkflowExecution.created_at.desc())
    
    total_count = len(list(db.execute(stmt).scalars().all()))
    
    offset = (page - 1) * page_size
    stmt = stmt.offset(offset).limit(page_size)
    
    executions = list(db.execute(stmt).scalars().all())
    
    return success_response(
        data={
            "items": [format_datetime_fields(e.__dict__, request) for e in executions],
            "total": total_count,
            "page": page,
            "page_size": page_size,
        },
        request=request,
        message="WORKFLOW_EXECUTIONS_LISTED",
    )


@router.get(
    "/businesses/{business_id}/workflows/{workflow_id}/executions/{execution_id}/logs",
    summary="لاگ‌های اجرای workflow",
    description="دریافت لاگ‌های یک اجرای workflow",
)
@require_business_access("business_id")
async def get_workflow_execution_logs(
    request: Request,
    business_id: int,
    workflow_id: int,
    execution_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """لاگ‌های اجرای workflow"""
    workflow = db.get(Workflow, workflow_id)
    if not workflow or workflow.business_id != business_id:
        raise ApiError("WORKFLOW_NOT_FOUND", "Workflow یافت نشد")
    
    execution = db.get(WorkflowExecution, execution_id)
    if not execution or execution.workflow_id != workflow_id:
        raise ApiError("EXECUTION_NOT_FOUND", "اجرای workflow یافت نشد")
    
    stmt = select(WorkflowLog).where(WorkflowLog.execution_id == execution_id)
    stmt = stmt.order_by(WorkflowLog.timestamp.asc())
    
    logs = list(db.execute(stmt).scalars().all())
    
    return success_response(
        data=[format_datetime_fields(log.__dict__, request) for log in logs],
        request=request,
        message="WORKFLOW_LOGS_RETRIEVED",
    )


@router.get(
    "/workflows/triggers",
    summary="لیست triggerهای موجود",
    description="دریافت لیست تمام triggerهای موجود",
)
async def list_triggers(
    request: Request,
):
    """لیست triggerهای موجود"""
    registry = TriggerRegistry()
    triggers = registry.list_triggers()
    
    return success_response(
        data=triggers,
        request=request,
        message="TRIGGERS_LISTED",
    )


@router.get(
    "/workflows/actions",
    summary="لیست actionهای موجود",
    description="دریافت لیست تمام actionهای موجود",
)
async def list_actions(
    request: Request,
):
    """لیست actionهای موجود"""
    registry = ActionRegistry()
    actions = registry.list_actions()
    
    return success_response(
        data=actions,
        request=request,
        message="ACTIONS_LISTED",
    )

