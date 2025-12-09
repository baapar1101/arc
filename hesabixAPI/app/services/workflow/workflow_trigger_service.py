"""
سرویس برای فراخوانی triggerهای workflow
این سرویس باید در نقاط مناسب سیستم فراخوانی شود
"""

import logging
from typing import Any, Dict, Optional
from sqlalchemy.orm import Session
from sqlalchemy import select, and_

from adapters.db.models.workflow import Workflow, WorkflowStatus
from app.services.workflow.workflow_engine import WorkflowEngine

logger = logging.getLogger(__name__)


def trigger_workflows(
    db: Session,
    business_id: int,
    trigger_type: str,
    trigger_data: Dict[str, Any],
    user_id: Optional[int] = None
) -> int:
    """
    فراخوانی workflowهای فعال که با trigger مشخص شده شروع می‌شوند
    
    Args:
        db: جلسه دیتابیس
        business_id: شناسه کسب‌وکار
        trigger_type: نوع trigger (مثل "invoice.created")
        trigger_data: داده‌های trigger
        user_id: شناسه کاربر (اختیاری)
    
    Returns:
        تعداد workflowهای اجرا شده
    """
    # پیدا کردن workflowهای فعال که با این trigger شروع می‌شوند
    stmt = select(Workflow).where(
        and_(
            Workflow.business_id == business_id,
            Workflow.status == WorkflowStatus.ACTIVE
        )
    )
    
    workflows = list(db.execute(stmt).scalars().all())
    
    executed_count = 0
    
    for workflow in workflows:
        workflow_data = workflow.workflow_data or {}
        nodes = workflow_data.get("nodes", [])
        
        # پیدا کردن trigger node
        trigger_node = None
        for node in nodes:
            if node.get("type") == "trigger":
                node_trigger_type = node.get("config", {}).get("trigger_type")
                if node_trigger_type == trigger_type:
                    trigger_node = node
                    break
        
        if not trigger_node:
            continue
        
        try:
            # اجرای workflow
            engine = WorkflowEngine(db, business_id, user_id)
            execution = engine.execute_workflow(workflow, trigger_data)
            
            if execution.status.value == "تکمیل شده":
                executed_count += 1
                logger.info(f"Workflow {workflow.id} executed successfully")
            else:
                logger.warning(f"Workflow {workflow.id} execution failed: {execution.error_message}")
        
        except Exception as e:
            logger.error(f"Error executing workflow {workflow.id}: {e}", exc_info=True)
    
    return executed_count


def trigger_invoice_created(
    db: Session,
    business_id: int,
    invoice_id: int,
    invoice_type: str,
    total_amount: float,
    user_id: Optional[int] = None
):
    """فراخوانی workflowها بعد از ایجاد فاکتور"""
    trigger_data = {
        "invoice_id": invoice_id,
        "invoice_type": invoice_type,
        "total_amount": total_amount,
        "document_id": invoice_id
    }
    
    # تعیین نوع تریگر خاص
    specific_trigger_type = None
    if invoice_type in ["invoice_sales", "sales"]:
        specific_trigger_type = "invoice.sales.created"
    elif invoice_type in ["invoice_purchase", "purchase"]:
        specific_trigger_type = "invoice.purchase.created"
    
    # اجرای ورک‌فلوهای عمومی با تریگر invoice.created
    executed_general = trigger_workflows(db, business_id, "invoice.created", trigger_data, user_id)
    
    # اجرای ورک‌فلوهای خاص (اگر وجود دارد)
    executed_specific = 0
    if specific_trigger_type:
        executed_specific = trigger_workflows(db, business_id, specific_trigger_type, trigger_data, user_id)
    
    return executed_general + executed_specific


def trigger_document_created(
    db: Session,
    business_id: int,
    document_id: int,
    document_type: str,
    user_id: Optional[int] = None
):
    """فراخوانی workflowها بعد از ایجاد سند"""
    trigger_data = {
        "document_id": document_id,
        "document_type": document_type
    }
    
    return trigger_workflows(db, business_id, "document.created", trigger_data, user_id)


def trigger_receipt_payment_created(
    db: Session,
    business_id: int,
    receipt_payment_id: int,
    type: str,  # receipt or payment
    amount: float,
    user_id: Optional[int] = None
):
    """فراخوانی workflowها بعد از ایجاد دریافت/پرداخت"""
    trigger_data = {
        "receipt_payment_id": receipt_payment_id,
        "type": type,
        "amount": amount
    }
    
    return trigger_workflows(db, business_id, "receipt_payment.created", trigger_data, user_id)


def trigger_person_created(
    db: Session,
    business_id: int,
    person_id: int,
    person_types: list,
    user_id: Optional[int] = None
):
    """فراخوانی workflowها بعد از ایجاد شخص"""
    trigger_data = {
        "person_id": person_id,
        "person_types": person_types
    }
    
    return trigger_workflows(db, business_id, "person.created", trigger_data, user_id)

