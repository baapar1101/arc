"""
عملیات workflow برای AI — reuse از validate، engine و مدل‌های موجود.
"""
from __future__ import annotations

import time
from typing import Any, Dict, List, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from adapters.db.models.workflow import (
    Workflow,
    WorkflowExecution,
    WorkflowExecutionStatus,
    WorkflowLog,
    WorkflowStatus,
)
from adapters.api.v1.workflows import (
    validate_workflow_data,
    ensure_workflow_webhook_settings,
)
from app.services.workflow.workflow_engine import WorkflowEngine
from app.services.workflow.dry_run import DRY_RUN_TRIGGER_KEY

AI_SANDBOX_WORKFLOW_NAME = "[AI] پیش‌نمایش آزمایشی"
_EXECUTION_POLL_INTERVAL_SEC = 0.35
_EXECUTION_POLL_TIMEOUT_SEC = 120


def workflow_editor_path(business_id: int, workflow_id: int, *, tab_index: int = 0) -> str:
    """
    مسیر نسبی برای کلاینت (با tab فعلی کاربر ساخته می‌شود).
    فیلد legacy `editor_url` برای سازگاری با tab0.
    """
    _ = business_id
    return f"workflows/{workflow_id}/edit"


def workflow_editor_url_legacy(business_id: int, workflow_id: int, *, tab_index: int = 0) -> str:
    return f"/business/{business_id}/tab{tab_index}/workflows/{workflow_id}/edit"


def _attach_editor_link(payload: Dict[str, Any], business_id: int) -> Dict[str, Any]:
    wid = payload.get("id") or payload.get("workflow_id")
    if wid is not None:
        payload["editor_path"] = workflow_editor_path(business_id, int(wid))
        payload["editor_url"] = workflow_editor_url_legacy(business_id, int(wid))
    return payload


def _workflow_status(value: Optional[str]) -> WorkflowStatus:
    if not value:
        return WorkflowStatus.DRAFT
    for s in WorkflowStatus:
        if s.value == value or s.name.lower() == str(value).lower():
            return s
    raise ValueError(f"وضعیت نامعتبر: {value}. مقادیر مجاز: پیش‌نویس، فعال، غیرفعال")


def _serialize_workflow(w: Workflow, *, include_graph: bool) -> Dict[str, Any]:
    data: Dict[str, Any] = {
        "id": w.id,
        "business_id": w.business_id,
        "name": w.name,
        "description": w.description,
        "status": w.status.value if hasattr(w.status, "value") else w.status,
        "settings": w.settings,
        "created_at": w.created_at.isoformat() if w.created_at else None,
        "updated_at": w.updated_at.isoformat() if w.updated_at else None,
    }
    if include_graph:
        data["workflow_data"] = w.workflow_data
    else:
        wd = w.workflow_data or {}
        nodes = wd.get("nodes") or []
        data["graph_summary"] = {
            "node_count": len(nodes),
            "connection_count": len(wd.get("connections") or []),
            "trigger_types": [
                (n.get("config") or {}).get("trigger_type")
                for n in nodes
                if isinstance(n, dict) and n.get("type") == "trigger"
            ],
        }
    return data


def _get_workflow_or_raise(db: Session, business_id: int, workflow_id: int) -> Workflow:
    w = db.get(Workflow, workflow_id)
    if not w or w.business_id != business_id:
        raise ValueError(f"Workflow {workflow_id} یافت نشد")
    return w


def validate_workflow_draft(workflow_data: Dict[str, Any]) -> Dict[str, Any]:
    errors = validate_workflow_data(workflow_data or {})
    return {"valid": len(errors) == 0, "errors": errors}


def create_workflow_for_ai(
    db: Session,
    business_id: int,
    user_id: Optional[int],
    *,
    name: str,
    workflow_data: Dict[str, Any],
    description: Optional[str] = None,
    status: Optional[str] = "پیش‌نویس",
    settings: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    if not name or not str(name).strip():
        raise ValueError("نام workflow الزامی است")
    validation = validate_workflow_draft(workflow_data)
    if not validation["valid"]:
        raise ValueError("workflow_data نامعتبر: " + "; ".join(validation["errors"]))

    merged_settings = ensure_workflow_webhook_settings(
        workflow_data, dict(settings or {})
    )
    workflow = Workflow(
        business_id=business_id,
        name=str(name).strip(),
        description=description,
        status=_workflow_status(status),
        workflow_data=workflow_data,
        settings=merged_settings if merged_settings else None,
        created_by_user_id=user_id,
    )
    db.add(workflow)
    db.commit()
    db.refresh(workflow)
    return _attach_editor_link(
        _serialize_workflow(workflow, include_graph=True), business_id
    )


def get_or_create_sandbox_workflow(
    db: Session,
    business_id: int,
    user_id: Optional[int],
) -> Workflow:
    """یک workflow پیش‌نمایش per business — برای تست workflow_data بدون اتوماسیون واقعی."""
    stmt = (
        select(Workflow)
        .where(
            Workflow.business_id == business_id,
            Workflow.name == AI_SANDBOX_WORKFLOW_NAME,
        )
        .limit(1)
    )
    existing = db.execute(stmt).scalars().first()
    if existing:
        return existing

    workflow = Workflow(
        business_id=business_id,
        name=AI_SANDBOX_WORKFLOW_NAME,
        description="فقط برای تست پیش‌نمایش از چت AI؛ قابل حذف.",
        status=WorkflowStatus.DRAFT,
        workflow_data={"nodes": [], "connections": []},
        settings={"ai_sandbox": True},
        created_by_user_id=user_id,
    )
    db.add(workflow)
    db.commit()
    db.refresh(workflow)
    return workflow


def update_workflow_for_ai(
    db: Session,
    business_id: int,
    workflow_id: int,
    *,
    name: Optional[str] = None,
    description: Optional[str] = None,
    status: Optional[str] = None,
    workflow_data: Optional[Dict[str, Any]] = None,
    settings: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    workflow = _get_workflow_or_raise(db, business_id, workflow_id)
    if name is not None:
        workflow.name = str(name).strip()
    if description is not None:
        workflow.description = description
    if status is not None:
        workflow.status = _workflow_status(status)
    if workflow_data is not None:
        validation = validate_workflow_draft(workflow_data)
        if not validation["valid"]:
            raise ValueError("workflow_data نامعتبر: " + "; ".join(validation["errors"]))
        workflow.workflow_data = workflow_data
        workflow.settings = ensure_workflow_webhook_settings(
            workflow_data, dict(workflow.settings or {})
        )
    if settings is not None:
        merged = dict(workflow.settings or {})
        merged.update(settings)
        workflow.settings = ensure_workflow_webhook_settings(
            workflow.workflow_data or {}, merged
        )
    db.commit()
    db.refresh(workflow)
    return _attach_editor_link(
        _serialize_workflow(workflow, include_graph=True), business_id
    )


def get_workflow_for_ai(
    db: Session,
    business_id: int,
    workflow_id: int,
    *,
    include_graph: bool = True,
) -> Dict[str, Any]:
    workflow = _get_workflow_or_raise(db, business_id, workflow_id)
    return _attach_editor_link(
        _serialize_workflow(workflow, include_graph=include_graph), business_id
    )


def delete_workflow_for_ai(db: Session, business_id: int, workflow_id: int) -> Dict[str, Any]:
    workflow = _get_workflow_or_raise(db, business_id, workflow_id)
    wid = workflow.id
    name = workflow.name
    db.delete(workflow)
    db.commit()
    return {"deleted": True, "workflow_id": wid, "name": name}


def _wait_for_execution(
    db: Session,
    execution_id: int,
    *,
    timeout_sec: float = _EXECUTION_POLL_TIMEOUT_SEC,
    poll_interval_sec: float = _EXECUTION_POLL_INTERVAL_SEC,
) -> WorkflowExecution:
    deadline = time.monotonic() + timeout_sec
    terminal = {
        WorkflowExecutionStatus.COMPLETED,
        WorkflowExecutionStatus.FAILED,
        WorkflowExecutionStatus.CANCELLED,
    }
    while time.monotonic() < deadline:
        db.expire_all()
        execution = db.get(WorkflowExecution, execution_id)
        if execution is None:
            raise ValueError(f"execution {execution_id} یافت نشد")
        if execution.status in terminal:
            return execution
        time.sleep(poll_interval_sec)
    execution = db.get(WorkflowExecution, execution_id)
    if execution is None:
        raise ValueError(f"execution {execution_id} یافت نشد")
    return execution


def test_workflow_for_ai(
    db: Session,
    business_id: int,
    user_id: Optional[int],
    workflow_id: Optional[int] = None,
    *,
    workflow_data: Optional[Dict[str, Any]] = None,
    trigger_data: Optional[Dict[str, Any]] = None,
    dry_run: bool = True,
    wait_for_completion: bool = True,
) -> Dict[str, Any]:
    """
    اجرای آزمایشی — حتی برای پیش‌نویس (برخلاف API عمومی که فقط فعال).

    - workflow_data: همیشه روی sandbox تست می‌شود (اتوماسیون واقعی کاربر دست‌نخورده می‌ماند).
    - فقط workflow_id: تست همان workflow ذخیره‌شده.
    """
    sandbox_used = False
    reference_workflow_id: Optional[int] = None
    if workflow_data is not None:
        validation = validate_workflow_draft(workflow_data)
        if not validation["valid"]:
            raise ValueError("workflow_data نامعتبر: " + "; ".join(validation["errors"]))

        reference_workflow_id = int(workflow_id) if workflow_id is not None else None
        workflow = get_or_create_sandbox_workflow(db, business_id, user_id)
        sandbox_used = True
        workflow.workflow_data = workflow_data
        workflow.settings = ensure_workflow_webhook_settings(
            workflow_data, dict(workflow.settings or {})
        )
        db.commit()
        db.refresh(workflow)
        workflow_id = workflow.id
    elif workflow_id is None:
        raise ValueError("workflow_id یا workflow_data الزامی است")
    else:
        workflow = _get_workflow_or_raise(db, business_id, int(workflow_id))

    td: Dict[str, Any] = dict(trigger_data or {})
    if dry_run:
        td[DRY_RUN_TRIGGER_KEY] = True

    engine = WorkflowEngine(db, business_id, user_id)
    execution = engine.execute_workflow(workflow, td)
    eid = execution.id
    wid = int(workflow_id)

    result: Dict[str, Any] = {
        "execution_id": eid,
        "workflow_id": wid,
        "status": getattr(execution.status, "value", str(execution.status)),
        "dry_run": dry_run,
        "workflow_status": workflow.status.value,
        "sandbox_used": sandbox_used,
        "reference_workflow_id": reference_workflow_id,
        "editor_path": workflow_editor_path(business_id, wid),
    }
    if sandbox_used:
        result["note"] = (
            "این تست روی پیش‌نمایش AI است؛ برای ویرایش نهایی create_workflow یا "
            "update_workflow را پس از تأیید کاربر اجرا کن."
        )

    if wait_for_completion and eid:
        execution = _wait_for_execution(db, eid)
        result["status"] = getattr(execution.status, "value", str(execution.status))
        result["debug"] = get_execution_debug_for_ai(
            db, business_id, wid, eid, max_logs=120
        )
        result["summary"] = summarize_execution_for_ai(db, business_id, wid, eid)

    return result


def get_execution_debug_for_ai(
    db: Session,
    business_id: int,
    workflow_id: int,
    execution_id: int,
    *,
    after_log_id: int = 0,
    max_logs: int = 80,
) -> Dict[str, Any]:
    workflow = _get_workflow_or_raise(db, business_id, workflow_id)
    execution = db.get(WorkflowExecution, execution_id)
    if not execution or execution.workflow_id != workflow.id:
        raise ValueError("اجرای workflow یافت نشد")

    stmt = (
        select(WorkflowLog)
        .where(WorkflowLog.execution_id == execution_id)
        .order_by(WorkflowLog.id.asc())
    )
    if after_log_id > 0:
        stmt = stmt.where(WorkflowLog.id > after_log_id)
    logs = list(db.execute(stmt.limit(max_logs)).scalars().all())

    errors = []
    node_events = []
    for log in logs:
        payload = log.data if isinstance(log.data, dict) else {}
        entry = {
            "id": log.id,
            "level": log.level.value if hasattr(log.level, "value") else log.level,
            "message": log.message,
            "node_id": payload.get("node_id"),
            "node_type": payload.get("node_type"),
            "timestamp": log.timestamp.isoformat() if log.timestamp else None,
        }
        node_events.append(entry)
        if entry["level"] == "error":
            errors.append(entry)

    return {
        "workflow_id": workflow_id,
        "workflow_name": workflow.name,
        "execution_id": execution_id,
        "execution_status": getattr(execution.status, "value", str(execution.status)),
        "started_at": execution.started_at.isoformat() if execution.started_at else None,
        "completed_at": execution.completed_at.isoformat() if execution.completed_at else None,
        "error_summary": errors[:10],
        "logs": node_events,
        "log_count": len(node_events),
        "has_more": len(logs) >= max_logs,
    }


def summarize_execution_for_ai(
    db: Session,
    business_id: int,
    workflow_id: int,
    execution_id: int,
) -> Dict[str, Any]:
    """خلاصه برای پاسخ چت بعد از test_workflow."""
    debug = get_execution_debug_for_ai(
        db, business_id, workflow_id, execution_id, max_logs=200
    )
    failed_nodes = [
        e for e in debug["logs"]
        if e.get("level") == "error" and e.get("node_id")
    ]
    return {
        "execution_id": execution_id,
        "status": debug["execution_status"],
        "failed_node_count": len(failed_nodes),
        "failed_nodes": failed_nodes[:5],
        "last_messages": [e.get("message") for e in debug["logs"][-5:]],
    }
