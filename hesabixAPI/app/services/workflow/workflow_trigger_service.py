"""
سرویس برای فراخوانی triggerهای workflow
این سرویس باید در نقاط مناسب سیستم فراخوانی شود
"""

import logging
import secrets
from datetime import date, datetime
from typing import Any, Dict, Optional
from sqlalchemy.orm import Session
from sqlalchemy import select, and_

from adapters.db.models.workflow import (
    Workflow,
    WorkflowStatus,
    WorkflowExecutionStatus,
)
from app.services.workflow.workflow_engine import WorkflowEngine

logger = logging.getLogger(__name__)


def build_invoice_trigger_enrichment(db: Session, document: Any) -> Dict[str, Any]:
    """
    فیلدهای تکمیلی trigger_data برای فاکتور تا با UI ورک‌فلو و قالب‌های پیام هم‌خوان باشد.
    """
    if document is None:
        return {}
    try:
        from adapters.db.models.document_line import DocumentLine
        from adapters.db.models.person import Person
    except Exception:
        return {}

    ex = document.extra_info or {}
    totals = ex.get("totals") or {}
    extra: Dict[str, Any] = {
        "invoice_code": document.code,
        "invoice_number": ex.get("invoice_number") or ex.get("invoice_no") or document.code,
        "discount_amount": float(totals.get("discount") or 0),
        "tax_amount": float(totals.get("tax") or 0),
        "final_amount": float(totals.get("net") or 0),
        "status": "proforma" if getattr(document, "is_proforma", False) else "confirmed",
    }
    dd = getattr(document, "document_date", None)
    if dd is not None:
        extra["invoice_date"] = dd.isoformat() if hasattr(dd, "isoformat") else str(dd)
    if getattr(document, "description", None):
        extra["description"] = document.description

    line = (
        db.query(DocumentLine)
        .filter(
            DocumentLine.document_id == document.id,
            DocumentLine.person_id.isnot(None),
        )
        .first()
    )
    if line and line.person_id:
        extra["customer_id"] = int(line.person_id)
        person = db.query(Person).filter(Person.id == line.person_id).first()
        if person:
            nm = (getattr(person, "alias_name", None) or "")
            nm = str(nm).strip()
            if nm:
                extra["customer_name"] = nm
    return {k: v for k, v in extra.items() if v is not None}


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
            from app.services.workflow.trigger_registry import TriggerRegistry

            preview_ctx: Dict[str, Any] = {
                "business_id": business_id,
                "user_id": user_id,
                "trigger_data": trigger_data,
                "workflow_id": workflow.id,
                "db": db,
                "__workflow_trigger_preview__": True,
            }
            tr = TriggerRegistry()
            th = tr.get_handler(trigger_type)
            if th:
                pre = th.execute(preview_ctx, trigger_node.get("config") or {})
                if not pre:
                    continue

            engine = WorkflowEngine(db, business_id, user_id)
            execution = engine.execute_workflow(workflow, trigger_data)
            
            if execution.status == WorkflowExecutionStatus.COMPLETED:
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
    user_id: Optional[int] = None,
    extra_fields: Optional[Dict[str, Any]] = None,
):
    """فراخوانی workflowها بعد از ایجاد فاکتور"""
    trigger_data = {
        "invoice_id": invoice_id,
        "invoice_type": invoice_type,
        "total_amount": total_amount,
        "document_id": invoice_id
    }
    if extra_fields:
        trigger_data.update(extra_fields)
    
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
    user_id: Optional[int] = None,
    extra_fields: Optional[Dict[str, Any]] = None,
):
    """فراخوانی workflowها بعد از ایجاد سند"""
    trigger_data = {
        "document_id": document_id,
        "document_type": document_type
    }
    if extra_fields:
        trigger_data.update(extra_fields)
    
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


def trigger_lead_created(
    db: Session,
    business_id: int,
    lead_id: int,
    process_definition_id: int,
    stage_id: int,
    name: str,
    user_id: Optional[int] = None,
):
    """فراخوانی workflowها بعد از ایجاد سرنخ"""
    trigger_data = {
        "lead_id": lead_id,
        "process_definition_id": process_definition_id,
        "stage_id": stage_id,
        "name": name,
    }
    return trigger_workflows(db, business_id, "crm.lead.created", trigger_data, user_id)


def trigger_lead_stage_changed(
    db: Session,
    business_id: int,
    lead_id: int,
    old_stage_id: int,
    new_stage_id: int,
    user_id: Optional[int] = None,
):
    """فراخوانی workflowها بعد از تغییر مرحله سرنخ"""
    trigger_data = {
        "lead_id": lead_id,
        "old_stage_id": old_stage_id,
        "new_stage_id": new_stage_id,
    }
    return trigger_workflows(db, business_id, "crm.lead.stage_changed", trigger_data, user_id)


def trigger_lead_converted(
    db: Session,
    business_id: int,
    lead_id: int,
    person_id: int,
    user_id: Optional[int] = None,
):
    """فراخوانی workflowها بعد از تبدیل سرنخ به مشتری"""
    trigger_data = {
        "lead_id": lead_id,
        "person_id": person_id,
    }
    return trigger_workflows(db, business_id, "crm.lead.converted", trigger_data, user_id)


def trigger_deal_created(
    db: Session,
    business_id: int,
    deal_id: int,
    process_definition_id: int,
    stage_id: int,
    person_id: int,
    title: str,
    amount: float,
    user_id: Optional[int] = None,
):
    """فراخوانی workflowها بعد از ایجاد فرصت فروش"""
    trigger_data = {
        "deal_id": deal_id,
        "process_definition_id": process_definition_id,
        "stage_id": stage_id,
        "person_id": person_id,
        "title": title,
        "amount": amount,
    }
    return trigger_workflows(db, business_id, "crm.deal.created", trigger_data, user_id)


def trigger_deal_stage_changed(
    db: Session,
    business_id: int,
    deal_id: int,
    old_stage_id: int,
    new_stage_id: int,
    user_id: Optional[int] = None,
):
    """فراخوانی workflowها بعد از تغییر مرحله فرصت فروش"""
    trigger_data = {
        "deal_id": deal_id,
        "old_stage_id": old_stage_id,
        "new_stage_id": new_stage_id,
    }
    return trigger_workflows(db, business_id, "crm.deal.stage_changed", trigger_data, user_id)


def trigger_deal_closed(
    db: Session,
    business_id: int,
    deal_id: int,
    amount: float,
    is_win: bool,
    document_id: Optional[int] = None,
    user_id: Optional[int] = None,
):
    """فراخوانی workflowها بعد از بستن معامله"""
    trigger_data = {
        "deal_id": deal_id,
        "amount": amount,
        "is_win": is_win,
        "document_id": document_id,
    }
    return trigger_workflows(db, business_id, "crm.deal.closed", trigger_data, user_id)


def ensure_workflow_webhook_settings(workflow_data: Dict[str, Any], settings: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """
    اگر ورک‌فلو تریگر webhook دارد، یک webhook_secret یکتا در settings قرار می‌دهد.
    """
    out = dict(settings or {})
    nodes = (workflow_data or {}).get("nodes") or []
    has_webhook = False
    for n in nodes:
        if not isinstance(n, dict):
            continue
        if n.get("type") != "trigger":
            continue
        cfg = n.get("config") or {}
        if cfg.get("trigger_type") == "webhook":
            has_webhook = True
            break
    if has_webhook and not out.get("webhook_secret"):
        out["webhook_secret"] = secrets.token_urlsafe(32)
    return out


def maybe_fire_inventory_low_triggers(
    db: Session,
    business_id: int,
    product_id: int,
    warehouse_id: Optional[int],
    user_id: Optional[int] = None,
) -> None:
    """
    پس از به‌روزرسانی موجودی: اگر کالا reorder_point دارد و موجودی به آن رسیده یا پایین‌تر است، تریگر inventory.low.
    """
    try:
        from adapters.db.models.product import Product
        from app.services.invoice_service import _compute_available_stock

        product = db.query(Product).filter(Product.id == int(product_id)).first()
        if not product or not getattr(product, "track_inventory", False):
            return
        min_q = getattr(product, "reorder_point", None)
        if min_q is None:
            return
        try:
            min_f = float(min_q)
        except (TypeError, ValueError):
            return
        if min_f < 0:
            return
        as_of = datetime.utcnow().date()
        current = float(
            _compute_available_stock(db, business_id, int(product_id), warehouse_id, as_of)
        )
        if current > min_f:
            return
        trigger_data: Dict[str, Any] = {
            "product_id": int(product_id),
            "current_quantity": current,
            "min_quantity": min_f,
        }
        if warehouse_id is not None:
            trigger_data["warehouse_id"] = int(warehouse_id)
        trigger_workflows(db, business_id, "inventory.low", trigger_data, user_id)
    except Exception as e:
        logger.warning("maybe_fire_inventory_low_triggers failed: %s", e, exc_info=True)


def _check_type_trigger_value(check_type: Any) -> str:
    from adapters.db.models.check import CheckType

    if check_type == CheckType.RECEIVED:
        return "received"
    return "paid"


def fire_check_due_workflow_triggers(
    db: Session,
    business_id: int,
    check_id: int,
    user_id: Optional[int] = None,
) -> int:
    """
    اجرای ورک‌فلوهایی با تریگر check.due_date برای یک چک مشخص.
    """
    from adapters.db.models.check import Check, CheckStatus

    terminal = {
        CheckStatus.CLEARED,
        CheckStatus.CANCELLED,
        CheckStatus.RETURNED,
        CheckStatus.BOUNCED,
    }
    check = db.query(Check).filter(Check.id == int(check_id), Check.business_id == int(business_id)).first()
    if not check:
        return 0
    if check.status is not None and check.status in terminal:
        return 0
    due = check.due_date
    due_d = due.date() if hasattr(due, "date") else due
    today = date.today()
    if isinstance(due_d, datetime):
        due_d = due_d.date()
    days_until_due = (due_d - today).days
    trigger_data: Dict[str, Any] = {
        "check_id": int(check.id),
        "check_number": check.check_number,
        "amount": float(check.amount),
        "check_type": _check_type_trigger_value(check.type),
        "due_date": due.isoformat() if hasattr(due, "isoformat") else str(due),
        "days_until_due": int(days_until_due),
    }
    if check.person_id:
        trigger_data["person_id"] = int(check.person_id)
    return trigger_workflows(db, business_id, "check.due_date", trigger_data, user_id)


def run_scheduled_workflow_fire(
    db: Session,
    business_id: int,
    workflow_id: int,
    user_id: Optional[int] = None,
) -> int:
    """
    اجرای یک ورک‌فلو با تریگر زمان‌بندی‌شده (پس از تطبیق cron در job بیرونی).
    """
    stmt = select(Workflow).where(
        and_(
            Workflow.id == int(workflow_id),
            Workflow.business_id == int(business_id),
            Workflow.status == WorkflowStatus.ACTIVE,
        )
    )
    workflow = db.execute(stmt).scalar_one_or_none()
    if not workflow:
        return 0
    trigger_data = {
        "_from_scheduler": True,
        "scheduled_at": datetime.utcnow().isoformat(),
    }
    try:
        engine = WorkflowEngine(db, business_id, user_id)
        execution = engine.execute_workflow(workflow, trigger_data)
        return 1 if execution.status == WorkflowExecutionStatus.COMPLETED else 0
    except Exception as e:
        logger.error("run_scheduled_workflow_fire failed wf=%s: %s", workflow_id, e, exc_info=True)
        return 0

