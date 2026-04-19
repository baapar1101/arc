"""
سرویس برای فراخوانی triggerهای workflow
این سرویس باید در نقاط مناسب سیستم فراخوانی شود
"""

import contextvars
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

_workflow_trigger_stack_depth: contextvars.ContextVar[int] = contextvars.ContextVar(
    "_workflow_trigger_stack_depth", default=0
)
MAX_NESTED_TRIGGER_DEPTH = 8


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
    depth = _workflow_trigger_stack_depth.get()
    if depth >= MAX_NESTED_TRIGGER_DEPTH:
        logger.warning(
            "trigger_workflows skipped (max nested depth %s): type=%s business_id=%s",
            MAX_NESTED_TRIGGER_DEPTH,
            trigger_type,
            business_id,
        )
        return 0
    depth_token = _workflow_trigger_stack_depth.set(depth + 1)
    try:
        return _trigger_workflows_inner(db, business_id, trigger_type, trigger_data, user_id)
    finally:
        _workflow_trigger_stack_depth.reset(depth_token)


def _trigger_workflows_inner(
    db: Session,
    business_id: int,
    trigger_type: str,
    trigger_data: Dict[str, Any],
    user_id: Optional[int] = None
) -> int:
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
    try:
        from app.services.workflow.workflow_trigger_enrichment import (
            build_document_trigger_enrichment,
        )

        enrichment = build_document_trigger_enrichment(db, business_id, document_id)
        trigger_data.update(enrichment)
    except Exception as e:
        logger.warning(
            "build_document_trigger_enrichment failed document_id=%s: %s",
            document_id,
            e,
            exc_info=True,
        )

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
    }
    try:
        from app.services.workflow.workflow_trigger_enrichment import (
            build_receipt_payment_trigger_enrichment,
        )

        enrichment = build_receipt_payment_trigger_enrichment(db, business_id, receipt_payment_id)
        trigger_data.update(enrichment)
    except Exception as e:
        logger.warning(
            "build_receipt_payment_trigger_enrichment failed document_id=%s: %s",
            receipt_payment_id,
            e,
            exc_info=True,
        )
    if trigger_data.get("amount") is None:
        trigger_data["amount"] = float(amount)

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


def build_crm_lead_trigger_enrichment(db: Session, business_id: int, lead_id: int) -> Dict[str, Any]:
    """فیلدهای تکمیلی برای قالب‌های پیام و شرط‌های ورک‌فلو."""
    try:
        from sqlalchemy.orm import joinedload
        from adapters.db.models.crm import Lead

        lead = (
            db.query(Lead)
            .options(
                joinedload(Lead.stage),
                joinedload(Lead.assigned_to),
                joinedload(Lead.person),
                joinedload(Lead.process_definition),
            )
            .filter(Lead.id == int(lead_id), Lead.business_id == int(business_id))
            .first()
        )
        if not lead:
            return {}
        extra: Dict[str, Any] = {
            "lead_code": lead.code,
            "stage_code": lead.stage.stage_code if lead.stage else None,
            "stage_name": lead.stage.name if lead.stage else None,
            "source_code": lead.source_code,
            "company_name": lead.company_name,
            "mobile": lead.mobile,
            "email": lead.email,
            "assigned_to_user_id": lead.assigned_to_user_id,
            "person_id": lead.person_id,
            "next_follow_up_at": lead.next_follow_up_at.isoformat() if lead.next_follow_up_at else None,
        }
        if lead.assigned_to:
            nm = f"{lead.assigned_to.first_name or ''} {lead.assigned_to.last_name or ''}".strip()
            if nm:
                extra["assigned_to_user_name"] = nm
        if lead.person:
            extra["person_name"] = (lead.person.alias_name or "").strip() or None
        if lead.process_definition:
            extra["process_definition_name"] = lead.process_definition.name
            extra["process_definition_code"] = lead.process_definition.code
        return {k: v for k, v in extra.items() if v is not None}
    except Exception as e:
        logger.warning("build_crm_lead_trigger_enrichment failed: %s", e)
        return {}


def build_crm_deal_trigger_enrichment(db: Session, business_id: int, deal_id: int) -> Dict[str, Any]:
    try:
        from sqlalchemy.orm import joinedload
        from adapters.db.models.crm import Deal

        deal = (
            db.query(Deal)
            .options(
                joinedload(Deal.stage),
                joinedload(Deal.assigned_to),
                joinedload(Deal.person),
                joinedload(Deal.process_definition),
            )
            .filter(Deal.id == int(deal_id), Deal.business_id == int(business_id))
            .first()
        )
        if not deal:
            return {}
        extra: Dict[str, Any] = {
            "deal_code": deal.code,
            "stage_code": deal.stage.stage_code if deal.stage else None,
            "stage_name": deal.stage.name if deal.stage else None,
            "title": deal.title,
            "amount": float(deal.amount),
            "probability_percent": deal.probability_percent,
            "assigned_to_user_id": deal.assigned_to_user_id,
            "person_id": deal.person_id,
            "document_id": deal.document_id,
            "next_follow_up_at": deal.next_follow_up_at.isoformat() if deal.next_follow_up_at else None,
            "expected_close_date": deal.expected_close_date.isoformat() if deal.expected_close_date else None,
        }
        if deal.assigned_to:
            nm = f"{deal.assigned_to.first_name or ''} {deal.assigned_to.last_name or ''}".strip()
            if nm:
                extra["assigned_to_user_name"] = nm
        if deal.person:
            extra["person_name"] = (deal.person.alias_name or "").strip() or None
        if deal.process_definition:
            extra["process_definition_name"] = deal.process_definition.name
            extra["process_definition_code"] = deal.process_definition.code
        return {k: v for k, v in extra.items() if v is not None}
    except Exception as e:
        logger.warning("build_crm_deal_trigger_enrichment failed: %s", e)
        return {}


def _crm_stage_pair_labels(db: Session, old_stage_id: Optional[int], new_stage_id: Optional[int]) -> Dict[str, Any]:
    from adapters.db.models.crm import CrmProcessStage

    ids = [sid for sid in (old_stage_id, new_stage_id) if sid is not None]
    if not ids:
        return {}
    rows = db.query(CrmProcessStage).filter(CrmProcessStage.id.in_(ids)).all()
    m = {r.id: (r.stage_code, r.name) for r in rows}
    out: Dict[str, Any] = {}
    if old_stage_id in m:
        out["old_stage_code"] = m[old_stage_id][0]
        out["old_stage_name"] = m[old_stage_id][1]
    if new_stage_id in m:
        out["new_stage_code"] = m[new_stage_id][0]
        out["new_stage_name"] = m[new_stage_id][1]
    return out


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
    trigger_data: Dict[str, Any] = {
        "lead_id": lead_id,
        "process_definition_id": process_definition_id,
        "stage_id": stage_id,
        "name": name,
    }
    trigger_data.update(build_crm_lead_trigger_enrichment(db, business_id, lead_id))
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
    trigger_data: Dict[str, Any] = {
        "lead_id": lead_id,
        "old_stage_id": old_stage_id,
        "new_stage_id": new_stage_id,
    }
    trigger_data.update(_crm_stage_pair_labels(db, old_stage_id, new_stage_id))
    trigger_data.update(build_crm_lead_trigger_enrichment(db, business_id, lead_id))
    return trigger_workflows(db, business_id, "crm.lead.stage_changed", trigger_data, user_id)


def trigger_lead_converted(
    db: Session,
    business_id: int,
    lead_id: int,
    person_id: int,
    user_id: Optional[int] = None,
):
    """فراخوانی workflowها بعد از تبدیل سرنخ به مشتری"""
    trigger_data: Dict[str, Any] = {
        "lead_id": lead_id,
        "person_id": person_id,
    }
    trigger_data.update(build_crm_lead_trigger_enrichment(db, business_id, lead_id))
    try:
        from adapters.db.models.person import Person

        person = db.query(Person).filter(Person.id == int(person_id), Person.business_id == int(business_id)).first()
        if person:
            trigger_data["person_name"] = (person.alias_name or "").strip() or None
    except Exception:
        pass
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
    trigger_data: Dict[str, Any] = {
        "deal_id": deal_id,
        "process_definition_id": process_definition_id,
        "stage_id": stage_id,
        "person_id": person_id,
        "title": title,
        "amount": amount,
    }
    trigger_data.update(build_crm_deal_trigger_enrichment(db, business_id, deal_id))
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
    trigger_data: Dict[str, Any] = {
        "deal_id": deal_id,
        "old_stage_id": old_stage_id,
        "new_stage_id": new_stage_id,
    }
    trigger_data.update(_crm_stage_pair_labels(db, old_stage_id, new_stage_id))
    trigger_data.update(build_crm_deal_trigger_enrichment(db, business_id, deal_id))
    return trigger_workflows(db, business_id, "crm.deal.stage_changed", trigger_data, user_id)


def trigger_deal_closed(
    db: Session,
    business_id: int,
    deal_id: int,
    amount: float,
    is_win: bool,
    document_id: Optional[int] = None,
    user_id: Optional[int] = None,
    is_lost: bool = False,
):
    """فراخوانی workflowها بعد از بستن معامله"""
    trigger_data: Dict[str, Any] = {
        "deal_id": deal_id,
        "amount": amount,
        "is_win": is_win,
        "is_lost": is_lost,
        "document_id": document_id,
    }
    trigger_data.update(build_crm_deal_trigger_enrichment(db, business_id, deal_id))
    return trigger_workflows(db, business_id, "crm.deal.closed", trigger_data, user_id)


def trigger_lead_assigned(
    db: Session,
    business_id: int,
    lead_id: int,
    old_assigned_to_user_id: Optional[int],
    new_assigned_to_user_id: Optional[int],
    user_id: Optional[int] = None,
) -> int:
    trigger_data: Dict[str, Any] = {
        "lead_id": lead_id,
        "old_assigned_to_user_id": old_assigned_to_user_id,
        "new_assigned_to_user_id": new_assigned_to_user_id,
    }
    trigger_data.update(build_crm_lead_trigger_enrichment(db, business_id, lead_id))
    return trigger_workflows(db, business_id, "crm.lead.assigned", trigger_data, user_id)


def trigger_deal_assigned(
    db: Session,
    business_id: int,
    deal_id: int,
    old_assigned_to_user_id: Optional[int],
    new_assigned_to_user_id: Optional[int],
    user_id: Optional[int] = None,
) -> int:
    trigger_data: Dict[str, Any] = {
        "deal_id": deal_id,
        "old_assigned_to_user_id": old_assigned_to_user_id,
        "new_assigned_to_user_id": new_assigned_to_user_id,
    }
    trigger_data.update(build_crm_deal_trigger_enrichment(db, business_id, deal_id))
    return trigger_workflows(db, business_id, "crm.deal.assigned", trigger_data, user_id)


def trigger_crm_activity_created(
    db: Session,
    business_id: int,
    activity_id: int,
    user_id: Optional[int] = None,
) -> int:
    try:
        from adapters.db.models.crm import CrmActivity

        act = (
            db.query(CrmActivity)
            .filter(CrmActivity.id == int(activity_id), CrmActivity.business_id == int(business_id))
            .first()
        )
        if not act:
            return 0
        td: Dict[str, Any] = {
            "activity_id": act.id,
            "activity_code": act.code,
            "activity_type": act.activity_type,
            "person_id": act.person_id,
            "lead_id": act.lead_id,
            "deal_id": act.deal_id,
            "subject": act.subject,
            "activity_date": act.activity_date.isoformat() if act.activity_date else None,
        }
        return trigger_workflows(db, business_id, "crm.activity.created", td, user_id)
    except Exception as e:
        logger.warning("trigger_crm_activity_created failed: %s", e)
        return 0


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


def trigger_distribution_visit_completed(
    db: Session,
    business_id: int,
    visit_id: int,
    user_id: Optional[int] = None,
) -> int:
    """فراخوانی ورک‌فلوها پس از تکمیل ویزیت میدانی (افزونه پخش مویرگی)."""
    try:
        from adapters.db.models.distribution import DistributionFieldVisit

        visit = (
            db.query(DistributionFieldVisit)
            .filter(DistributionFieldVisit.id == int(visit_id), DistributionFieldVisit.business_id == int(business_id))
            .first()
        )
        if not visit:
            return 0
        trigger_data: Dict[str, Any] = {
            "visit_id": int(visit.id),
            "person_id": int(visit.person_id),
            "user_id": int(visit.user_id),
            "route_id": int(visit.route_id) if visit.route_id else None,
            "status": visit.status,
            "outcome": visit.outcome,
            "document_id": int(visit.document_id) if visit.document_id else None,
            "deal_id": int(visit.deal_id) if visit.deal_id else None,
            "started_at": visit.started_at.isoformat() if visit.started_at else None,
            "ended_at": visit.ended_at.isoformat() if visit.ended_at else None,
        }
        return trigger_workflows(db, business_id, "distribution.visit.completed", trigger_data, user_id)
    except Exception as e:
        logger.warning("trigger_distribution_visit_completed failed: %s", e, exc_info=True)
        return 0

