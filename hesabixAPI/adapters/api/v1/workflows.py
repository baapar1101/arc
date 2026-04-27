"""
API endpoints برای مدیریت Workflow
"""

from collections import defaultdict
import asyncio
import json
import logging
from typing import Any, Dict, List, Optional
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, Request, Body, HTTPException, Query, BackgroundTasks
from sqlalchemy.orm import Session
from sqlalchemy import select, and_, or_, func, cast, Text, case, text

from adapters.db.session import get_db
from adapters.db.models.workflow import (
    Workflow,
    WorkflowStatus,
    WorkflowExecution,
    WorkflowExecutionStatus,
    WorkflowLog,
    WorkflowLogLevel,
)
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.responses import success_response, format_datetime_fields, ApiError
from app.services.workflow.workflow_engine import WorkflowEngine
from app.services.workflow.trigger_registry import TriggerRegistry
from app.services.workflow.action_registry import ActionRegistry
from app.services.workflow.workflow_trigger_service import ensure_workflow_webhook_settings
from app.core.settings import get_settings as get_app_settings
from adapters.api.v1.schemas import QueryInfo

router = APIRouter(tags=["workflows"])
_logger = logging.getLogger(__name__)


def _workflow_background_run(
    execution_id: int,
    workflow_id: int,
    business_id: int,
    user_id: Optional[int],
    trigger_data: Dict[str, Any],
) -> None:
    """اجرای workflow در پس‌زمینه پس از پاسخ HTTP (برای نمایش زنده در کلاینت)."""
    from adapters.db.session import SessionLocal

    db = SessionLocal()
    try:
        workflow = db.get(Workflow, workflow_id)
        execution = db.get(WorkflowExecution, execution_id)
        if not workflow or not execution:
            _logger.error("workflow background: workflow or execution missing")
            return
        if execution.workflow_id != workflow_id:
            _logger.error("workflow background: execution workflow mismatch")
            return
        if workflow.business_id != business_id:
            _logger.error("workflow background: business mismatch")
            return
        if execution.status != WorkflowExecutionStatus.PENDING:
            _logger.warning(
                "workflow background: execution %s status is %s, skip",
                execution_id,
                execution.status,
            )
            return
        engine = WorkflowEngine(db, business_id, user_id)
        engine.run_pending_execution(workflow, execution, trigger_data)
    except Exception as e:
        _logger.error("workflow background run failed: %s", e, exc_info=True)
    finally:
        db.close()


def _webhook_trigger_timeout_seconds(workflow: Workflow) -> float:
    """timeout_seconds از نود تریگر webhook (۵…۶۰۰ ثانیه)."""
    nodes = (workflow.workflow_data or {}).get("nodes") or []
    for n in nodes:
        if not isinstance(n, dict):
            continue
        if n.get("type") != "trigger":
            continue
        cfg = n.get("config") or {}
        if cfg.get("trigger_type") != "webhook":
            continue
        raw = cfg.get("timeout_seconds", 30)
        try:
            t = float(raw)
        except (TypeError, ValueError):
            t = 30.0
        return max(5.0, min(t, 600.0))
    return 30.0


def _attach_workflow_webhook_url(data: Dict[str, Any], request: Request) -> None:
    settings_row = data.get("settings")
    secret = (settings_row or {}).get("webhook_secret") if isinstance(settings_row, dict) else None
    if not secret:
        return
    try:
        root = str(request.base_url).rstrip("/")
        prefix = get_app_settings().api_v1_prefix.rstrip("/")
        data["webhook_inbound_url"] = f"{root}{prefix}/workflow-hooks/{secret}"
    except Exception:
        pass


def validate_workflow_data(workflow_data: Dict[str, Any]) -> List[str]:
    """
    اعتبارسنجی ساختار workflow_data
    
    Args:
        workflow_data: داده‌های workflow برای validation
        
    Returns:
        لیست خطاها (خالی اگر معتبر باشد)
    """
    errors = []
    
    if not isinstance(workflow_data, dict):
        errors.append("workflow_data باید یک dictionary باشد")
        return errors
    
    # بررسی وجود nodes
    nodes = workflow_data.get("nodes", [])
    if not isinstance(nodes, list):
        errors.append("nodes باید یک لیست باشد")
        return errors
    
    if len(nodes) == 0:
        errors.append("workflow باید حداقل یک node داشته باشد")
        return errors
    
    # بررسی وجود connections
    connections = workflow_data.get("connections", [])
    if not isinstance(connections, list):
        errors.append("connections باید یک لیست باشد")
        return errors
    
    # بررسی ساختار هر node
    node_ids = set()
    for i, node in enumerate(nodes):
        if not isinstance(node, dict):
            errors.append(f"node در index {i} باید یک dictionary باشد")
            continue
        
        node_id = node.get("id")
        if not node_id:
            errors.append(f"node در index {i} باید دارای id باشد")
            continue
        
        if node_id in node_ids:
            errors.append(f"node با id تکراری '{node_id}' یافت شد")
        node_ids.add(node_id)
        
        node_type = node.get("type")
        if node_type not in ["trigger", "action", "condition", "loop"]:
            errors.append(f"node '{node_id}' دارای type نامعتبر '{node_type}' است")
        
        if not node.get("label"):
            errors.append(f"node '{node_id}' باید دارای label باشد")
    
    # بررسی ساختار connections
    for i, conn in enumerate(connections):
        if not isinstance(conn, dict):
            errors.append(f"connection در index {i} باید یک dictionary باشد")
            continue
        
        source = conn.get("source")
        target = conn.get("target")
        
        if not source or not target:
            errors.append(f"connection در index {i} باید دارای source و target باشد")
            continue
        
        if source not in node_ids:
            errors.append(f"connection در index {i} به node ناموجود '{source}' اشاره می‌کند")
        
        if target not in node_ids:
            errors.append(f"connection در index {i} به node ناموجود '{target}' اشاره می‌کند")
    
    # بررسی حداقل یک trigger
    trigger_nodes = [n for n in nodes if isinstance(n, dict) and n.get("type") == "trigger"]
    if len(trigger_nodes) == 0:
        errors.append("workflow باید حداقل یک trigger node داشته باشد")

    # تریگر زمان‌بندی: باید کرون معتبر یا حالت سادهٔ قابل تبدیل داشته باشد
    try:
        from app.services.workflow.schedule_cron_resolution import schedule_config_is_valid

        for n in trigger_nodes:
            cfg = (n.get("config") or {}) if isinstance(n, dict) else {}
            if cfg.get("trigger_type") != "scheduled":
                continue
            if not schedule_config_is_valid(cfg):
                errors.append(
                    "تریگر زمان‌بندی‌شده: عبارت کرون را وارد کنید یا حالت ساده را کامل کنید"
                )
                break
    except Exception:
        pass
    
    # بررسی محدودیت اندازه
    import json
    workflow_data_size = len(json.dumps(workflow_data))
    max_size = 10 * 1024 * 1024  # 10 MB
    if workflow_data_size > max_size:
        errors.append(f"اندازه workflow_data ({workflow_data_size} bytes) بیش از حد مجاز ({max_size} bytes) است")
    
    return errors


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
    
    # اعتبارسنجی ساختار workflow_data
    validation_errors = validate_workflow_data(workflow_data)
    if validation_errors:
        raise ApiError(
            "WORKFLOW_DATA_INVALID",
            f"ساختار workflow_data نامعتبر است: {'; '.join(validation_errors)}"
        )
    
    merged_settings = ensure_workflow_webhook_settings(
        workflow_data, dict(body.get("settings") or {})
    )

    workflow = Workflow(
        business_id=business_id,
        name=name,
        description=body.get("description"),
        status=WorkflowStatus(body.get("status", WorkflowStatus.DRAFT.value)),
        workflow_data=workflow_data,
        settings=merged_settings if merged_settings else None,
        created_by_user_id=ctx.get_user_id(),
    )
    
    db.add(workflow)
    db.commit()
    db.refresh(workflow)

    created = format_datetime_fields(workflow.__dict__, request)
    _attach_workflow_webhook_url(created, request)

    return success_response(
        data=created,
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

    payload = format_datetime_fields(workflow.__dict__, request)
    _attach_workflow_webhook_url(payload, request)

    return success_response(
        data=payload,
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
        # اعتبارسنجی ساختار workflow_data
        validation_errors = validate_workflow_data(body["workflow_data"])
        if validation_errors:
            raise ApiError(
                "WORKFLOW_DATA_INVALID",
                f"ساختار workflow_data نامعتبر است: {'; '.join(validation_errors)}"
            )
        workflow.workflow_data = body["workflow_data"]
        workflow.settings = ensure_workflow_webhook_settings(
            body["workflow_data"], dict(workflow.settings or {})
        )
    if "settings" in body:
        merged = dict(workflow.settings or {})
        merged.update(body["settings"] or {})
        workflow.settings = ensure_workflow_webhook_settings(
            workflow.workflow_data or {}, merged
        )
    
    db.commit()
    db.refresh(workflow)

    updated = format_datetime_fields(workflow.__dict__, request)
    _attach_workflow_webhook_url(updated, request)

    return success_response(
        data=updated,
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
    description="اجرای دستی. بدنه می‌تواند `dry_run: true` باشد (آزمایشی، بدون ارسال/ثبت واقعی).",
)
@require_business_access("business_id")
async def execute_workflow(
    request: Request,
    business_id: int,
    workflow_id: int,
    background_tasks: BackgroundTasks,
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
    
    raw_trigger = body.get("trigger_data")
    trigger_data: Dict[str, Any] = raw_trigger if isinstance(raw_trigger, dict) else {}
    async_execution = bool(body.get("async_execution", False))
    dry_run = bool(body.get("dry_run", False))
    if dry_run:
        from app.services.workflow.dry_run import DRY_RUN_TRIGGER_KEY

        if isinstance(trigger_data, dict):
            trigger_data = {**trigger_data, DRY_RUN_TRIGGER_KEY: True}
        else:
            trigger_data = {DRY_RUN_TRIGGER_KEY: True}

    engine = WorkflowEngine(db, business_id, ctx.get_user_id())

    if async_execution:
        execution = engine.create_pending_execution(workflow, trigger_data)
        background_tasks.add_task(
            _workflow_background_run,
            execution.id,
            workflow_id,
            business_id,
            ctx.get_user_id(),
            trigger_data,
        )
    else:
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
    
    # شمارش کل با استفاده از func.count() برای کارایی بهتر
    count_stmt = select(func.count(WorkflowExecution.id)).where(
        WorkflowExecution.workflow_id == workflow_id
    )
    total_count = db.execute(count_stmt).scalar_one() or 0
    
    # دریافت لیست با pagination
    stmt = select(WorkflowExecution).where(WorkflowExecution.workflow_id == workflow_id)
    stmt = stmt.order_by(WorkflowExecution.created_at.desc())
    
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
    "/businesses/{business_id}/workflows/{workflow_id}/executions/{execution_id}",
    summary="جزئیات یک اجرای workflow",
    description="دریافت وضعیت یک اجرا (برای polling هنگام اجرای ناهمزمان)",
)
@require_business_access("business_id")
async def get_workflow_execution(
    request: Request,
    business_id: int,
    workflow_id: int,
    execution_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    workflow = db.get(Workflow, workflow_id)
    if not workflow or workflow.business_id != business_id:
        raise ApiError("WORKFLOW_NOT_FOUND", "Workflow یافت نشد")

    execution = db.get(WorkflowExecution, execution_id)
    if not execution or execution.workflow_id != workflow_id:
        raise ApiError("EXECUTION_NOT_FOUND", "اجرای workflow یافت نشد")

    return success_response(
        data=format_datetime_fields(execution.__dict__, request),
        request=request,
        message="WORKFLOW_EXECUTION_RETRIEVED",
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
    after_log_id: Optional[int] = Query(
        None,
        ge=0,
        description="فقط لاگ‌های با id بزرگ‌تر از این مقدار (polling افزایشی؛ ۰ یعنی از ابدا)",
    ),
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
    if after_log_id is not None and after_log_id > 0:
        stmt = stmt.where(WorkflowLog.id > after_log_id)
    stmt = stmt.order_by(WorkflowLog.id.asc())
    
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


@router.get(
    "/businesses/{business_id}/workflows/analytics/errors",
    summary="تحلیل خطاهای workflow",
    description="دریافت آمار و تحلیل خطاهای workflow در بازه زمانی مشخص",
)
@require_business_access("business_id")
async def get_workflow_errors_analytics(
    request: Request,
    business_id: int,
    days: int = Query(7, ge=1, le=90, description="تعداد روزهای گذشته"),
    workflow_id: Optional[int] = Query(None, description="فیلتر بر اساس workflow خاص"),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """تحلیل خطاهای workflow"""
    
    # Query پایه - واکشی در Python برای سازگاری با دیتابیس و data=None
    stmt = select(WorkflowLog).select_from(WorkflowLog).join(
        WorkflowExecution, WorkflowExecution.id == WorkflowLog.execution_id
    ).join(Workflow, Workflow.id == WorkflowExecution.workflow_id).where(
        and_(
            Workflow.business_id == business_id,
            WorkflowLog.level == WorkflowLogLevel.ERROR,
            WorkflowLog.timestamp >= datetime.utcnow() - timedelta(days=days)
        )
    )
    if workflow_id:
        stmt = stmt.where(Workflow.id == workflow_id)
    
    logs = list(db.execute(stmt).scalars().all())
    
    # گروه‌بندی در Python
    error_stats = defaultdict(lambda: {"count": 0, "last_occurrence": None, "first_occurrence": None})
    for log in logs:
        data = log.data or {}
        error_type = data.get("error_type") or data.get("error_message") or "Unknown"
        if isinstance(error_type, str) and len(error_type) > 100:
            error_type = error_type[:100] + "..."
        else:
            error_type = str(error_type)
        error_stats[error_type]["count"] += 1
        ts = log.timestamp
        if error_stats[error_type]["last_occurrence"] is None or ts > error_stats[error_type]["last_occurrence"]:
            error_stats[error_type]["last_occurrence"] = ts
        if error_stats[error_type]["first_occurrence"] is None or ts < error_stats[error_type]["first_occurrence"]:
            error_stats[error_type]["first_occurrence"] = ts
    
    total_errors = sum(s["count"] for s in error_stats.values())
    results = sorted(
        [{"error_type": k, "count": v["count"], "last_occurrence": v["last_occurrence"], "first_occurrence": v["first_occurrence"]} for k, v in error_stats.items()],
        key=lambda x: x["count"],
        reverse=True
    )
    
    return success_response(
        data={
            "total_errors": total_errors,
            "unique_error_types": len(results),
            "period_days": days,
            "errors_by_type": [
                {
                    "error_type": r["error_type"],
                    "count": r["count"],
                    "percentage": round((r["count"] / total_errors * 100), 2) if total_errors > 0 else 0,
                    "last_occurrence": format_datetime_fields({"timestamp": r["last_occurrence"]}, request)["timestamp"],
                    "first_occurrence": format_datetime_fields({"timestamp": r["first_occurrence"]}, request)["timestamp"]
                }
                for r in results
            ]
        },
        request=request,
        message="WORKFLOW_ERRORS_ANALYTICS_RETRIEVED",
    )


@router.get(
    "/businesses/{business_id}/workflows/analytics/performance",
    summary="تحلیل عملکرد workflows",
    description="دریافت آمار عملکرد workflows شامل تعداد اجراها، نرخ موفقیت، و میانگین زمان اجرا",
)
@require_business_access("business_id")
async def get_workflow_performance_analytics(
    request: Request,
    business_id: int,
    workflow_id: Optional[int] = Query(None, description="فیلتر بر اساس workflow خاص"),
    days: int = Query(30, ge=1, le=365, description="تعداد روزهای گذشته"),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """تحلیل عملکرد workflows"""
    
    # Query پایه - برای database-agnostic بودن، duration را در Python محاسبه می‌کنیم
    stmt = select(
        Workflow.id,
        Workflow.name,
        Workflow.status,
        func.count(WorkflowExecution.id).label('total_executions'),
        func.count(
            case(
                (WorkflowExecution.status == WorkflowExecutionStatus.COMPLETED, 1),
            )
        ).label('successful'),
        func.count(
            case(
                (WorkflowExecution.status == WorkflowExecutionStatus.FAILED, 1),
            )
        ).label('failed'),
    ).select_from(Workflow) \
     .outerjoin(WorkflowExecution, WorkflowExecution.workflow_id == Workflow.id) \
     .where(
         and_(
             Workflow.business_id == business_id,
             or_(
                 WorkflowExecution.created_at >= datetime.utcnow() - timedelta(days=days),
                 WorkflowExecution.created_at.is_(None)
             )
         )
     )
    
    # فیلتر بر اساس workflow
    if workflow_id:
        stmt = stmt.where(Workflow.id == workflow_id)
    
    stmt = stmt.group_by(Workflow.id, Workflow.name, Workflow.status) \
               .order_by(func.count(WorkflowExecution.id).desc())
    
    results = list(db.execute(stmt).all())
    
    # محاسبه duration برای هر workflow در Python (database-agnostic)
    workflow_stats = []
    for r in results:
        # دریافت executions برای محاسبه duration
        exec_stmt = select(WorkflowExecution).where(
            and_(
                WorkflowExecution.workflow_id == r.id,
                WorkflowExecution.created_at >= datetime.utcnow() - timedelta(days=days),
                WorkflowExecution.started_at.isnot(None),
                WorkflowExecution.completed_at.isnot(None),
            )
        )
        executions = list(db.execute(exec_stmt).scalars().all())
        
        durations = []
        for exec in executions:
            if exec.started_at and exec.completed_at:
                duration = (exec.completed_at - exec.started_at).total_seconds()
                durations.append(duration)
        
        avg_duration = sum(durations) / len(durations) if durations else 0
        min_duration = min(durations) if durations else 0
        max_duration = max(durations) if durations else 0
        
        workflow_stats.append({
            "workflow_id": r.id,
            "workflow_name": r.name,
            "workflow_status": r.status.value if r.status else None,
            "total_executions": r.total_executions or 0,
            "successful": r.successful or 0,
            "failed": r.failed or 0,
            "success_rate": round(
                (r.successful / r.total_executions * 100) if r.total_executions > 0 else 0,
                2
            ),
            "avg_duration_seconds": round(avg_duration, 2),
            "min_duration_seconds": round(min_duration, 2),
            "max_duration_seconds": round(max_duration, 2)
        })
    
    return success_response(
        data={
            "period_days": days,
            "workflows": workflow_stats
        },
        request=request,
        message="WORKFLOW_PERFORMANCE_ANALYTICS_RETRIEVED",
    )


@router.get(
    "/businesses/{business_id}/workflows/{workflow_id}/executions/{execution_id}/timeline",
    summary="Timeline اجرای workflow",
    description="دریافت timeline دقیق اجرای workflow برای debugging",
)
@require_business_access("business_id")
async def get_execution_timeline(
    request: Request,
    business_id: int,
    workflow_id: int,
    execution_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """دریافت timeline اجرای workflow"""
    
    # بررسی وجود workflow
    workflow = db.get(Workflow, workflow_id)
    if not workflow or workflow.business_id != business_id:
        raise ApiError("WORKFLOW_NOT_FOUND", "Workflow یافت نشد")
    
    # بررسی وجود execution
    execution = db.get(WorkflowExecution, execution_id)
    if not execution or execution.workflow_id != workflow_id:
        raise ApiError("EXECUTION_NOT_FOUND", "اجرای workflow یافت نشد")
    
    # دریافت تمام لاگ‌ها
    logs_stmt = select(WorkflowLog) \
        .where(WorkflowLog.execution_id == execution_id) \
        .order_by(WorkflowLog.timestamp.asc())
    
    logs = list(db.execute(logs_stmt).scalars().all())
    
    # ساخت timeline
    timeline = []
    node_stats = {}
    
    for log in logs:
        # اضافه به timeline
        log_data = {
            "timestamp": format_datetime_fields({"t": log.timestamp}, request)["t"],
            "level": log.level.value if hasattr(log.level, 'value') else str(log.level),
            "message": log.message,
            "node_id": log.node_id,
            "data": log.data
        }
        timeline.append(log_data)
        
        # محاسبه آمار nodeها
        if log.node_id:
            if log.node_id not in node_stats:
                node_stats[log.node_id] = {
                    "node_id": log.node_id,
                    "executions": 0,
                    "errors": 0,
                    "total_duration_ms": 0,
                    "node_type": log.data.get("node_type") if log.data else None,
                    "node_label": log.data.get("node_label") if log.data else None
                }
            
            node_stats[log.node_id]["executions"] += 1
            
            if log.level.value == 'error' or (hasattr(log.level, 'value') and log.level.value == 'error'):
                node_stats[log.node_id]["errors"] += 1
            
            if log.data and "duration_ms" in log.data:
                node_stats[log.node_id]["total_duration_ms"] += log.data["duration_ms"]
    
    # محاسبه میانگین duration برای هر node
    for node_id, stats in node_stats.items():
        if stats["executions"] > 0:
            stats["avg_duration_ms"] = round(
                stats["total_duration_ms"] / stats["executions"],
                2
            )
    
    # محاسبه مدت زمان کلی
    duration_seconds = None
    if execution.completed_at and execution.started_at:
        duration_seconds = (execution.completed_at - execution.started_at).total_seconds()
    
    return success_response(
        data={
            "execution": {
                "id": execution.id,
                "workflow_id": execution.workflow_id,
                "workflow_name": workflow.name,
                "status": execution.status.value if hasattr(execution.status, 'value') else str(execution.status),
                "started_at": format_datetime_fields({"t": execution.started_at}, request)["t"] if execution.started_at else None,
                "completed_at": format_datetime_fields({"t": execution.completed_at}, request)["t"] if execution.completed_at else None,
                "duration_seconds": round(duration_seconds, 2) if duration_seconds else None,
                "error_message": execution.error_message
            },
            "timeline": timeline,
            "node_statistics": list(node_stats.values()),
            "summary": {
                "total_logs": len(logs),
                "total_nodes": len(node_stats),
                "error_count": sum(1 for log in logs if log.level.value == 'error' or str(log.level) == 'error')
            }
        },
        request=request,
        message="EXECUTION_TIMELINE_RETRIEVED",
    )


@router.get(
    "/workflows/metadata/triggers",
    summary="دریافت metadata triggerها",
    description="دریافت لیست triggerهای موجود با metadata",
)
async def get_triggers_metadata(
    request: Request,
    lang: str = Query("fa", description="زبان (fa/en)"),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """دریافت metadata triggerها"""
    from app.services.workflow.i18n import translate_trigger_metadata, TRIGGER_TRANSLATIONS_BY_KEY

    trigger_registry = TriggerRegistry()
    all_triggers = trigger_registry.get_all_metadata()
    out = []
    for t in all_triggers:
        key = t.get("key") or ""
        if key in TRIGGER_TRANSLATIONS_BY_KEY:
            out.append(translate_trigger_metadata(t, lang, key))
        else:
            out.append(t)

    return success_response(
        data=out,
        request=request,
        message="TRIGGERS_METADATA_RETRIEVED",
    )


@router.get(
    "/workflows/metadata/actions",
    summary="دریافت metadata actionها",
    description="دریافت لیست actionهای موجود با metadata",
)
async def get_actions_metadata(
    request: Request,
    lang: str = Query("fa", description="زبان (fa/en)"),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """دریافت metadata actionها با پشتیبانی از ترجمه"""
    from app.services.workflow.i18n import translate_metadata
    from app.services.workflow.i18n.hesabix_data_actions_i18n import get_workflow_action_keys

    _wf_data_action_keys = get_workflow_action_keys()

    action_registry = ActionRegistry()
    all_actions = action_registry.get_all_metadata()
    
    # ترجمه metadata برای هر action
    translated_actions = []
    for action in all_actions:
        action_key = action.get("key", "")
        
        # تعیین context برای ترجمه
        translation_context = None
        if action_key == "ai_agent":
            translation_context = "ai_agent"
        elif action_key == "business_backup":
            translation_context = "business_backup"
        elif action_key == "crm_web_chat_send_message":
            translation_context = "crm_web_chat_send_message"
        elif "invoice" in action_key and "create" in action_key:
            translation_context = "create_invoice"
        elif "bale" in action_key:
            translation_context = "send_bale"
        elif "telegram" in action_key:
            translation_context = "send_telegram"
        elif "email" in action_key:
            translation_context = "send_email"
        elif action_key in _wf_data_action_keys:
            translation_context = action_key

        # ترجمه metadata
        if translation_context:
            translated = translate_metadata(action, lang, translation_context)
        else:
            translated = action
        
        translated_actions.append(translated)
    
    return success_response(
        data=translated_actions,
        request=request,
        message="ACTIONS_METADATA_RETRIEVED",
    )


@router.get(
    "/workflows/translations",
    summary="دریافت تمام ترجمه‌های ورک‌فلو",
    description="دریافت تمام رشته‌های ترجمه شده برای استفاده در UI",
)
async def get_workflow_translations(
    request: Request,
    lang: str = Query("fa", description="زبان (fa/en)"),
    ctx: AuthContext = Depends(get_current_user),
):
    """دریافت تمام ترجمه‌های ورک‌فلو"""
    from app.services.workflow.i18n import (
        COMMON_TRANSLATIONS,
        CREATE_INVOICE_TRANSLATIONS,
        SEND_TELEGRAM_TRANSLATIONS,
        SEND_EMAIL_TRANSLATIONS,
        OTHER_ACTIONS_TRANSLATIONS,
        BUSINESS_BACKUP_TRANSLATIONS,
    )
    from app.services.workflow.i18n.hesabix_data_actions_i18n import WORKFLOW_ACTION_TRANSLATIONS
    from app.services.workflow.i18n.workflow_translations import (
        TRIGGER_TRANSLATIONS_BY_KEY,
        CRM_WEB_CHAT_SEND_MESSAGE_TRANSLATIONS,
    )

    all_translations: dict = {}
    all_translations.update(COMMON_TRANSLATIONS.get(lang, {}))
    all_translations["create_invoice"] = CREATE_INVOICE_TRANSLATIONS.get(lang, {})
    all_translations["send_telegram"] = SEND_TELEGRAM_TRANSLATIONS.get(lang, {})
    all_translations["send_email"] = SEND_EMAIL_TRANSLATIONS.get(lang, {})
    all_translations["others"] = OTHER_ACTIONS_TRANSLATIONS.get(lang, {})
    all_translations["business_backup"] = BUSINESS_BACKUP_TRANSLATIONS.get(lang, {})
    all_translations["crm_web_chat_send_message"] = CRM_WEB_CHAT_SEND_MESSAGE_TRANSLATIONS.get(lang, {})

    for _tk, _bundle in TRIGGER_TRANSLATIONS_BY_KEY.items():
        all_translations[_tk] = _bundle.get(lang, {})
    for _ak, _abundle in WORKFLOW_ACTION_TRANSLATIONS.items():
        all_translations[_ak] = _abundle.get(lang, {})
    
    return success_response(
        data={
            "language": lang,
            "translations": all_translations
        },
        request=request,
        message="TRANSLATIONS_RETRIEVED",
    )


@router.get(
    "/workflows/translations/export",
    summary="صادرات ترجمه‌ها برای Flutter",
    description="صادرات ترجمه‌های ورک‌فلو به فرمت مناسب برای فایل‌های arb",
)
async def export_workflow_translations(
    request: Request,
    lang: str = Query("fa", description="زبان (fa/en)"),
    ctx: AuthContext = Depends(get_current_user),
):
    """صادرات ترجمه‌ها به فرمت arb"""
    from app.services.workflow.i18n import (
        COMMON_TRANSLATIONS,
        CREATE_INVOICE_TRANSLATIONS,
        SEND_TELEGRAM_TRANSLATIONS,
        SEND_EMAIL_TRANSLATIONS,
        OTHER_ACTIONS_TRANSLATIONS,
    )
    
    # تبدیل به فرمت arb (flat structure با prefix)
    arb_translations = {}
    
    # مشترک
    for key, value in COMMON_TRANSLATIONS.get(lang, {}).items():
        arb_translations[f"workflow_{key}"] = value
    
    # Create Invoice
    for key, value in CREATE_INVOICE_TRANSLATIONS.get(lang, {}).items():
        arb_translations[f"workflowCreateInvoice_{key}"] = value
    
    # Send Telegram
    for key, value in SEND_TELEGRAM_TRANSLATIONS.get(lang, {}).items():
        arb_translations[f"workflowSendTelegram_{key}"] = value
    
    # Send Email
    for key, value in SEND_EMAIL_TRANSLATIONS.get(lang, {}).items():
        arb_translations[f"workflowSendEmail_{key}"] = value
    
    # Others
    for key, value in OTHER_ACTIONS_TRANSLATIONS.get(lang, {}).items():
        arb_translations[f"workflowOthers_{key}"] = value
    
    return success_response(
        data={
            "language": lang,
            "format": "arb",
            "translations": arb_translations,
            "total_keys": len(arb_translations)
        },
        request=request,
        message="TRANSLATIONS_EXPORTED",
    )


@router.api_route(
    "/workflow-hooks/{webhook_secret}",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"],
    summary="اجرای ورک‌فلو از طریق Webhook",
    description="بدون احراز هویت کاربر؛ فقط با webhook_secret ذخیره‌شده در تنظیمات ورک‌فلو.",
)
async def workflow_webhook_inbound(
    request: Request,
    webhook_secret: str,
    db: Session = Depends(get_db),
):
    secret = (webhook_secret or "").strip()
    if len(secret) < 16:
        raise ApiError("WORKFLOW_WEBHOOK_NOT_FOUND", "نشانی webhook نامعتبر است", http_status=404)

    stmt = select(Workflow).where(Workflow.status == WorkflowStatus.ACTIVE)
    candidates = list(db.execute(stmt).scalars().all())
    wf = next(
        (w for w in candidates if (w.settings or {}).get("webhook_secret") == secret),
        None,
    )
    if wf is None:
        raise ApiError("WORKFLOW_WEBHOOK_NOT_FOUND", "ورک‌فلو فعال با این نشانی یافت نشد", http_status=404)

    nodes = (wf.workflow_data or {}).get("nodes") or []
    has_webhook_trigger = any(
        isinstance(n, dict)
        and n.get("type") == "trigger"
        and (n.get("config") or {}).get("trigger_type") == "webhook"
        for n in nodes
    )
    if not has_webhook_trigger:
        raise ApiError(
            "WORKFLOW_WEBHOOK_DISABLED",
            "این ورک‌فلو تریگر webhook ندارد",
            http_status=400,
        )

    raw_body = await request.body()
    body_obj: Any = {}
    if raw_body:
        try:
            body_obj = json.loads(raw_body.decode("utf-8"))
        except Exception:
            body_obj = {"_raw_text": raw_body.decode("utf-8", errors="replace")}

    trigger_data: Dict[str, Any] = {
        "method": request.method,
        "headers": {k: v for k, v in request.headers.items()},
        "query_params": dict(request.query_params),
        "body": body_obj,
    }

    timeout_sec = _webhook_trigger_timeout_seconds(wf)

    def _run_workflow_sync():
        engine = WorkflowEngine(db, wf.business_id, user_id=None)
        return engine.execute_workflow(wf, trigger_data)

    try:
        execution = await asyncio.wait_for(
            asyncio.to_thread(_run_workflow_sync),
            timeout=timeout_sec,
        )
    except asyncio.TimeoutError:
        raise ApiError(
            "WORKFLOW_WEBHOOK_TIMEOUT",
            f"اجرای ورک‌فلو بیش از {int(timeout_sec)} ثانیه طول کشید",
            http_status=504,
        )
    except ApiError:
        raise
    except Exception as e:
        _logger.error("workflow webhook execute failed: %s", e, exc_info=True)
        raise ApiError("WORKFLOW_WEBHOOK_EXEC_FAILED", str(e), http_status=500)

    return success_response(
        data=format_datetime_fields(execution.__dict__, request),
        request=request,
        message="WORKFLOW_WEBHOOK_EXECUTED",
    )

