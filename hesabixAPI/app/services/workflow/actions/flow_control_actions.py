"""
کنترل جریان: تأخیر، عبارت (SimpleEval)، اجرای زیر-گردش کار
"""

from __future__ import annotations

import copy
import logging
import time
from typing import Any, Dict

from simpleeval import SimpleEval

from app.services.workflow.action_registry import ActionHandler
from app.services.workflow.logging_decorators import log_action_execution
from app.services.workflow.workflow_engine import WorkflowEngine

logger = logging.getLogger(__name__)

MAX_SUB_WORKFLOW_DEPTH = 5
MAX_WAIT_SECONDS = 300


class WaitAction(ActionHandler):
    """تأخیر ثابت (ثانیه) — برای فاصله‌اندازی یا انتظار ساده (بدون انتظار رویداد خارجی)"""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "تأخیر (ثانیه)",
            "description": f"مکث اجرا به مدت N ثانیه (حداکثر {MAX_WAIT_SECONDS} ثانیه)",
            "config_schema": {
                "seconds": {
                    "type": "number",
                    "description": "مدت مکث بر حسب ثانیه",
                    "required": True,
                },
            },
        }

    @log_action_execution
    def execute(self, context: Dict[str, Any], config: Dict[str, Any], node_results: Dict[str, Any]) -> Dict[str, Any]:
        raw = WorkflowEngine._resolve_value_static(config.get("seconds", 0), context, node_results)
        try:
            sec = float(raw)
        except (TypeError, ValueError):
            sec = 0.0
        sec = max(0.0, min(float(sec), float(MAX_WAIT_SECONDS)))
        t0 = time.time()
        time.sleep(sec)
        return {
            "success": True,
            "waited_seconds": sec,
            "elapsed_ms": round((time.time() - t0) * 1000, 2),
        }


class CodeExpressionAction(ActionHandler):
    """
    محاسبه عبارت امن با SimpleEval (مشابه بخش Expression در n8n).
    نام‌ها: trigger_data, node_results, variables, context
    """

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "عبارت (کد امن)",
            "description": "ارزیابی عبارت با simpleeval (بدون import و دسترسی ناامن)",
            "config_schema": {
                "expression": {
                    "type": "string",
                    "description": "مثال: len(trigger_data) > 0  یا  node_results",
                    "required": True,
                    "ui_type": "textarea",
                },
            },
        }

    @log_action_execution
    def execute(self, context: Dict[str, Any], config: Dict[str, Any], node_results: Dict[str, Any]) -> Dict[str, Any]:
        expression = config.get("expression")
        if not expression:
            return {"success": False, "error": "expression is required"}
        expr = str(WorkflowEngine._resolve_value_static(expression, context, node_results))

        # کپی سطحی تا تغییرات داخلی روی context اصلی اثر نگذارد
        safe_trigger = copy.deepcopy(context.get("trigger_data") or {})
        safe_vars = copy.deepcopy(context.get("variables") or {})
        safe_nodes = copy.deepcopy(node_results or {})

        evaluator = SimpleEval(
            names={
                "trigger_data": safe_trigger,
                "node_results": safe_nodes,
                "variables": safe_vars,
                "context": {
                    "business_id": context.get("business_id"),
                    "user_id": context.get("user_id"),
                    "workflow_id": context.get("workflow_id"),
                    "execution_id": context.get("execution_id"),
                },
            },
            functions={
                "len": len,
                "str": str,
                "int": int,
                "float": float,
                "bool": bool,
                "abs": abs,
                "min": min,
                "max": max,
                "sum": sum,
                "round": round,
            },
        )
        try:
            out = evaluator.eval(expr)
        except Exception as e:
            logger.error("CodeExpressionAction eval failed: %s", e, exc_info=True)
            return {"success": False, "error": str(e)}

        return {"success": True, "result": out}


class SubWorkflowAction(ActionHandler):
    """اجرای کامل یک گردش کار دیگر با همان business و ادغام trigger_data"""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "زیر-گردش کار",
            "description": f"فراخوانی گردش کار فعال دیگر (حداکثر {MAX_SUB_WORKFLOW_DEPTH} سطح تودرتو)",
            "config_schema": {
                "target_workflow_id": {
                    "type": "integer",
                    "description": "شناسه گردش کار مقصد (همان کسب‌وکار)",
                    "required": True,
                },
                "input": {
                    "type": "object",
                    "description": "داده اضافه روی trigger_data زیر-گردش",
                    "required": False,
                },
            },
        }

    @log_action_execution
    def execute(self, context: Dict[str, Any], config: Dict[str, Any], node_results: Dict[str, Any]) -> Dict[str, Any]:
        from adapters.db.models.workflow import Workflow, WorkflowStatus

        db = context.get("db")
        business_id = int(context.get("business_id"))
        user_id = context.get("user_id")

        wf_id = WorkflowEngine._resolve_value_static(config.get("target_workflow_id"), context, node_results)
        try:
            wf_id = int(wf_id)
        except (TypeError, ValueError):
            return {"success": False, "error": "target_workflow_id must be an integer"}

        extra = config.get("input") or {}
        extra = WorkflowEngine._resolve_value_static(extra, context, node_results)
        if extra is not None and not isinstance(extra, dict):
            return {"success": False, "error": "input must be an object/dict when provided"}
        extra = extra or {}

        td = context.get("trigger_data")
        if not isinstance(td, dict):
            td = {}
        depth = 0
        try:
            depth = int(td.get("__sub_workflow_depth", 0))
        except (TypeError, ValueError):
            depth = 0
        if depth >= MAX_SUB_WORKFLOW_DEPTH:
            return {"success": False, "error": "MAX_SUB_WORKFLOW_DEPTH_EXCEEDED", "depth": depth}

        wf = (
            db.query(Workflow)
            .filter(
                Workflow.id == wf_id,
                Workflow.business_id == business_id,
                Workflow.status == WorkflowStatus.ACTIVE,
            )
            .first()
        )
        if not wf:
            return {"success": False, "error": "WORKFLOW_NOT_FOUND_OR_INACTIVE", "target_workflow_id": wf_id}

        from app.services.workflow.dry_run import DRY_RUN_TRIGGER_KEY

        child_trigger = {**td, **extra, "__sub_workflow_depth": depth + 1}
        if context.get("dry_run"):
            child_trigger[DRY_RUN_TRIGGER_KEY] = True

        engine = WorkflowEngine(db, business_id, user_id)
        try:
            execution = engine.execute_workflow(wf, child_trigger)
        except Exception as e:
            logger.error("SubWorkflowAction execute_workflow failed: %s", e, exc_info=True)
            return {"success": False, "error": str(e), "target_workflow_id": wf_id}

        from adapters.db.models.workflow import WorkflowExecutionStatus

        ex_data = execution.execution_data if hasattr(execution, "execution_data") else None
        ok = bool(execution.status == WorkflowExecutionStatus.COMPLETED)
        return {
            "success": ok,
            "target_workflow_id": wf_id,
            "child_execution_id": execution.id,
            "child_status": execution.status.value if execution.status else None,
            "child_error": getattr(execution, "error_message", None),
            "result": ex_data,
        }
