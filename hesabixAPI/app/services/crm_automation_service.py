# noqa: D100
"""سرویس اتوماسیون فروش CRM.

شامل:
- امتیازدهی سرنخ (lead scoring)
- تخصیص خودکار round-robin
- تعیین SLA سرنخ
- توالی‌های خودکار (sequences) و پردازش آن‌ها
- یادآوری پیگیری، وظایف سررسید گذشته و نقض SLA
- علامت‌گذاری فرصت‌های راکد

کانال‌های اعلان مرتبط با ایران: تلگرام، بله، پیامک و داخل‌برنامه‌ای (WhatsApp پیاده‌سازی نمی‌شود).

کلیدهای رویداد نوتیفیکیشن که این ماژول استفاده می‌کند (در صورت نبود قالب، پیام داخل‌برنامه‌ای ساخته می‌شود):
- crm.follow_up_due
- crm.task_overdue
- crm.lead_sla_breach
- crm.deal_stale
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, date
from typing import Any, Dict, List, Optional

from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from adapters.db.models.crm import (
    Lead,
    Deal,
    CrmActivity,
    CrmProcessStage,
    CrmSequence,
    CrmSequenceStep,
    CrmSequenceEnrollment,
    CrmReminderDedup,
)
from adapters.db.models.business import Business
from adapters.db.models.person import Person
from adapters.db.models.business_crm_settings import BusinessCrmSettings

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# تنظیمات
# ---------------------------------------------------------------------------


def _get_settings(db: Session, business_id: int) -> BusinessCrmSettings:
    from app.services.crm_chat_service import get_or_create_crm_settings

    return get_or_create_crm_settings(db, business_id)


# ---------------------------------------------------------------------------
# امتیازدهی سرنخ
# ---------------------------------------------------------------------------

DEFAULT_SCORE_RULES: Dict[str, Any] = {
    "has_mobile": 10,
    "has_email": 10,
    "has_company": 15,
    "stage_multiplier": 2,
    "source_weights": {},
}


def compute_lead_score(lead: Lead, rules: Optional[Dict[str, Any]] = None) -> int:
    """موتور ساده امتیازدهی سرنخ بر اساس فیلدهای موجود و قوانین کسب‌وکار."""
    r = dict(DEFAULT_SCORE_RULES)
    if rules:
        r.update({k: v for k, v in rules.items() if v is not None})
    score = 0
    try:
        if lead.mobile:
            score += int(r.get("has_mobile", 10))
        if lead.email:
            score += int(r.get("has_email", 10))
        if lead.company_name:
            score += int(r.get("has_company", 15))
        source_weights = r.get("source_weights") or {}
        if lead.source_code and lead.source_code in source_weights:
            score += int(source_weights[lead.source_code])
        # امتیاز بر اساس ترتیب مرحله (هرچه جلوتر، امتیاز بیشتر)
        stage = getattr(lead, "stage", None)
        if stage is not None and stage.order_index is not None:
            score += int(stage.order_index) * int(r.get("stage_multiplier", 2))
    except Exception:
        logger.exception("compute_lead_score failed")
    return max(0, score)


def apply_lead_score(db: Session, business_id: int, lead: Lead) -> int:
    settings = _get_settings(db, business_id)
    score = compute_lead_score(lead, settings.score_rules)
    lead.score = score
    return score


# ---------------------------------------------------------------------------
# تخصیص خودکار round-robin
# ---------------------------------------------------------------------------


def apply_auto_assign(db: Session, business_id: int, lead: Lead) -> Optional[int]:
    """در صورت فعال بودن، سرنخ بدون مسئول را به‌صورت گردشی به یک کاربر تخصیص می‌دهد."""
    if lead.assigned_to_user_id:
        return lead.assigned_to_user_id
    settings = _get_settings(db, business_id)
    if not settings.auto_assign_enabled:
        return None
    user_ids = settings.auto_assign_user_ids or []
    if not isinstance(user_ids, list) or not user_ids:
        return None
    cursor = int(settings.auto_assign_cursor or 0) % len(user_ids)
    chosen = user_ids[cursor]
    lead.assigned_to_user_id = int(chosen)
    settings.auto_assign_cursor = (cursor + 1) % len(user_ids)
    return int(chosen)


# ---------------------------------------------------------------------------
# SLA سرنخ
# ---------------------------------------------------------------------------


def set_lead_sla(db: Session, business_id: int, lead: Lead) -> Optional[datetime]:
    """تعیین مهلت SLA برای اولین تماس بر اساس تنظیمات کسب‌وکار."""
    settings = _get_settings(db, business_id)
    hours = int(settings.lead_sla_hours or 0)
    if hours <= 0:
        return None
    lead.sla_due_at = datetime.utcnow() + timedelta(hours=hours)
    return lead.sla_due_at


# ---------------------------------------------------------------------------
# ابزار اعلان
# ---------------------------------------------------------------------------


def _resolve_target_user_id(db: Session, business_id: int, assigned_to_user_id: Optional[int]) -> Optional[int]:
    if assigned_to_user_id:
        return int(assigned_to_user_id)
    b = db.get(Business, business_id)
    if b and getattr(b, "owner_id", None):
        return int(b.owner_id)
    return None


def _notify(
    db: Session,
    *,
    user_id: Optional[int],
    event_key: str,
    title: str,
    message: str,
    business_id: int,
    entity_type: str,
    entity_id: int,
    deep_link: Optional[str] = None,
) -> bool:
    """ارسال اعلان با NotificationService؛ در نبود قالب هم پیام داخل‌برنامه‌ای ساخته می‌شود."""
    if not user_id:
        return False
    try:
        from app.services.notification_service import NotificationService

        context = {
            "subject": title,
            "title": title,
            "message": message,
            "business_id": business_id,
            "entity_type": entity_type,
            "entity_id": entity_id,
        }
        if deep_link:
            context["deep_link"] = deep_link
        return NotificationService(db).send(
            user_id=int(user_id),
            event_key=event_key,
            context=context,
            preferred_channels=["inapp", "telegram", "bale", "sms", "email"],
        )
    except Exception:
        logger.exception("crm _notify failed event=%s", event_key)
        return False


def _send_customer_sms(db: Session, mobile: Optional[str], text: str) -> bool:
    """ارسال پیامک مستقیم به مشتری (نه کاربر سامانه) با تنظیمات مرکزی پیامک."""
    if not mobile or not text:
        return False
    try:
        from app.services.system_settings_service import get_effective_notifications_settings
        from app.services.providers.sms_provider import SmsProvider
        from app.utils.phone_utils import normalize_phone_number

        cfg = get_effective_notifications_settings(db)
        sms = SmsProvider(
            provider_name=cfg.get("sms_provider_name"),
            api_key=cfg.get("sms_api_key"),
            sender=cfg.get("sms_sender"),
            username=cfg.get("sms_provider_username"),
            password=cfg.get("sms_provider_password"),
            is_flash=cfg.get("sms_is_flash", False),
        )
        if not sms.is_configured():
            return False
        ok, _ = sms.send_text_with_error(to_phone=normalize_phone_number(mobile), text=text)
        return bool(ok)
    except Exception:
        logger.exception("crm _send_customer_sms failed")
        return False


# ---------------------------------------------------------------------------
# جلوگیری از ارسال تکراری
# ---------------------------------------------------------------------------


def _already_sent(db: Session, business_id: int, entity_type: str, entity_id: int, reminder_key: str) -> bool:
    row = (
        db.query(CrmReminderDedup.id)
        .filter(
            CrmReminderDedup.business_id == business_id,
            CrmReminderDedup.entity_type == entity_type,
            CrmReminderDedup.entity_id == entity_id,
            CrmReminderDedup.reminder_key == reminder_key,
        )
        .first()
    )
    return row is not None


def _mark_sent(db: Session, business_id: int, entity_type: str, entity_id: int, reminder_key: str) -> None:
    db.add(
        CrmReminderDedup(
            business_id=business_id,
            entity_type=entity_type,
            entity_id=entity_id,
            reminder_key=reminder_key,
        )
    )


# ---------------------------------------------------------------------------
# توالی‌ها (Sequences)
# ---------------------------------------------------------------------------


def enroll_in_sequence(
    db: Session,
    business_id: int,
    sequence_id: int,
    entity_type: str,
    entity_id: int,
) -> CrmSequenceEnrollment:
    from app.core.responses import ApiError

    if entity_type not in ("lead", "deal"):
        raise ApiError("CRM_SEQ_INVALID_ENTITY", "entity_type باید lead یا deal باشد.", http_status=400)
    seq = (
        db.query(CrmSequence)
        .filter(and_(CrmSequence.id == sequence_id, CrmSequence.business_id == business_id))
        .first()
    )
    if not seq or not seq.is_active:
        raise ApiError("CRM_SEQ_NOT_FOUND", "توالی یافت نشد یا غیرفعال است.", http_status=404)

    # اعتبارسنجی وجود موجودیت
    if entity_type == "lead":
        ent = db.query(Lead.id).filter(Lead.id == entity_id, Lead.business_id == business_id).first()
    else:
        ent = db.query(Deal.id).filter(Deal.id == entity_id, Deal.business_id == business_id).first()
    if not ent:
        raise ApiError("NOT_FOUND", "موجودیت مورد نظر یافت نشد.", http_status=404)

    # جلوگیری از ثبت‌نام تکراری فعال
    existing = (
        db.query(CrmSequenceEnrollment)
        .filter(
            CrmSequenceEnrollment.business_id == business_id,
            CrmSequenceEnrollment.sequence_id == sequence_id,
            CrmSequenceEnrollment.entity_type == entity_type,
            CrmSequenceEnrollment.entity_id == entity_id,
            CrmSequenceEnrollment.status == "active",
        )
        .first()
    )
    if existing:
        return existing

    first_step = (
        db.query(CrmSequenceStep)
        .filter(CrmSequenceStep.sequence_id == sequence_id)
        .order_by(CrmSequenceStep.step_order.asc())
        .first()
    )
    now = datetime.utcnow()
    enrollment = CrmSequenceEnrollment(
        business_id=business_id,
        sequence_id=sequence_id,
        entity_type=entity_type,
        entity_id=entity_id,
        status="active",
        current_step_order=0,
        next_run_at=(now + timedelta(hours=int(first_step.delay_hours or 0))) if first_step else None,
    )
    if not first_step:
        enrollment.status = "completed"
        enrollment.completed_at = now
    db.add(enrollment)
    db.flush()
    return enrollment


def _execute_sequence_step(db: Session, enrollment: CrmSequenceEnrollment, step: CrmSequenceStep) -> None:
    """اجرای یک گام از توالی."""
    from app.services.document_numbering_service import generate_document_code

    business_id = enrollment.business_id
    config = step.action_config or {}
    now = datetime.utcnow()

    lead: Optional[Lead] = None
    deal: Optional[Deal] = None
    if enrollment.entity_type == "lead":
        lead = db.query(Lead).filter(Lead.id == enrollment.entity_id, Lead.business_id == business_id).first()
    else:
        deal = db.query(Deal).filter(Deal.id == enrollment.entity_id, Deal.business_id == business_id).first()

    if enrollment.entity_type == "lead" and not lead:
        return
    if enrollment.entity_type == "deal" and not deal:
        return

    action = step.action_type

    if action == "create_task":
        assigned = (lead.assigned_to_user_id if lead else deal.assigned_to_user_id)
        created_by = assigned or _resolve_target_user_id(db, business_id, None)
        if not created_by:
            return
        due_in = int(config.get("due_in_hours", 24) or 24)
        try:
            code_val = generate_document_code(db, business_id, "crm_activity", date.today())
        except Exception:
            code_val = f"SEQ-{enrollment.id}-{step.id}"
        task = CrmActivity(
            business_id=business_id,
            person_id=(deal.person_id if deal else (lead.person_id if lead else None)),
            lead_id=(lead.id if lead else None),
            deal_id=(deal.id if deal else None),
            code=code_val,
            activity_type="task",
            subject=config.get("subject") or "پیگیری توالی خودکار",
            description=config.get("description"),
            activity_date=now,
            is_task=True,
            status="open",
            due_at=now + timedelta(hours=due_in),
            assigned_to_user_id=assigned,
            priority=config.get("priority", "normal"),
            created_by_user_id=created_by,
        )
        db.add(task)

    elif action == "send_sms":
        mobile = None
        if lead:
            mobile = lead.mobile
        elif deal:
            person = db.get(Person, deal.person_id) if deal.person_id else None
            mobile = person.mobile if person else None
        text = config.get("message") or config.get("text") or ""
        _send_customer_sms(db, mobile, text)

    elif action == "notify_assignee":
        assigned = (lead.assigned_to_user_id if lead else deal.assigned_to_user_id)
        target = _resolve_target_user_id(db, business_id, assigned)
        title = config.get("title") or "یادآوری توالی CRM"
        message = config.get("message") or "گام توالی خودکار برای پیگیری فرا رسید."
        _notify(
            db,
            user_id=target,
            event_key="crm.follow_up_due",
            title=title,
            message=message,
            business_id=business_id,
            entity_type=enrollment.entity_type,
            entity_id=enrollment.entity_id,
        )

    elif action == "update_lead_stage" and lead:
        stage_id = config.get("stage_id")
        if stage_id:
            stage = (
                db.query(CrmProcessStage)
                .filter(
                    CrmProcessStage.id == int(stage_id),
                    CrmProcessStage.process_definition_id == lead.process_definition_id,
                )
                .first()
            )
            if stage:
                lead.stage_id = stage.id

    elif action == "update_deal_stage" and deal:
        stage_id = config.get("stage_id")
        if stage_id:
            stage = (
                db.query(CrmProcessStage)
                .filter(
                    CrmProcessStage.id == int(stage_id),
                    CrmProcessStage.process_definition_id == deal.process_definition_id,
                )
                .first()
            )
            if stage:
                deal.stage_id = stage.id
                deal.stage_entered_at = now


def tick_sequences(db: Session) -> Dict[str, int]:
    """پردازش ثبت‌نام‌های سررسیده در توالی‌ها."""
    now = datetime.utcnow()
    stats = {"processed": 0, "completed": 0, "errors": 0}
    enrollments = (
        db.query(CrmSequenceEnrollment)
        .filter(
            CrmSequenceEnrollment.status == "active",
            CrmSequenceEnrollment.next_run_at.isnot(None),
            CrmSequenceEnrollment.next_run_at <= now,
        )
        .limit(500)
        .all()
    )
    for enr in enrollments:
        try:
            next_step = (
                db.query(CrmSequenceStep)
                .filter(
                    CrmSequenceStep.sequence_id == enr.sequence_id,
                    CrmSequenceStep.step_order > enr.current_step_order,
                )
                .order_by(CrmSequenceStep.step_order.asc())
                .first()
            )
            if not next_step:
                enr.status = "completed"
                enr.completed_at = now
                stats["completed"] += 1
                continue
            _execute_sequence_step(db, enr, next_step)
            enr.current_step_order = next_step.step_order
            enr.last_error = None
            stats["processed"] += 1
            # زمان‌بندی گام بعدی
            following = (
                db.query(CrmSequenceStep)
                .filter(
                    CrmSequenceStep.sequence_id == enr.sequence_id,
                    CrmSequenceStep.step_order > enr.current_step_order,
                )
                .order_by(CrmSequenceStep.step_order.asc())
                .first()
            )
            if following:
                enr.next_run_at = now + timedelta(hours=int(following.delay_hours or 0))
            else:
                enr.status = "completed"
                enr.completed_at = now
                enr.next_run_at = None
                stats["completed"] += 1
        except Exception as e:
            stats["errors"] += 1
            enr.last_error = str(e)[:1000]
            logger.exception("tick_sequences enrollment=%s failed", enr.id)
    try:
        db.commit()
    except Exception:
        db.rollback()
    return stats


# ---------------------------------------------------------------------------
# یادآوری پیگیری، وظایف سررسید گذشته و نقض SLA
# ---------------------------------------------------------------------------

_settings_cache: Dict[int, BusinessCrmSettings] = {}


def _follow_up_enabled(db: Session, business_id: int) -> bool:
    try:
        settings = _get_settings(db, business_id)
        return bool(settings.follow_up_notify_enabled)
    except Exception:
        return True


def process_follow_up_reminders(db: Session) -> Dict[str, int]:
    """یادآوری پیگیری سرنخ/فرصت، وظایف سررسید گذشته و نقض SLA سرنخ."""
    now = datetime.utcnow()
    horizon = now + timedelta(hours=1)
    stats = {"follow_up": 0, "task_overdue": 0, "sla_breach": 0}

    # --- پیگیری سرنخ‌ها (تبدیل‌نشده و باز) ---
    lead_rows = (
        db.query(Lead)
        .filter(
            Lead.next_follow_up_at.isnot(None),
            Lead.next_follow_up_at <= horizon,
            Lead.person_id.is_(None),
        )
        .limit(500)
        .all()
    )
    for lead in lead_rows:
        if not _follow_up_enabled(db, lead.business_id):
            continue
        key = f"follow_up:{lead.next_follow_up_at.isoformat()}"
        if _already_sent(db, lead.business_id, "lead", lead.id, key):
            continue
        target = _resolve_target_user_id(db, lead.business_id, lead.assigned_to_user_id)
        ok = _notify(
            db,
            user_id=target,
            event_key="crm.follow_up_due",
            title="یادآوری پیگیری سرنخ",
            message=f"زمان پیگیری سرنخ «{lead.name}» فرا رسیده است.",
            business_id=lead.business_id,
            entity_type="lead",
            entity_id=lead.id,
        )
        _mark_sent(db, lead.business_id, "lead", lead.id, key)
        if ok:
            stats["follow_up"] += 1

    # --- پیگیری فرصت‌های فروش (باز) ---
    deal_rows = (
        db.query(Deal)
        .filter(
            Deal.next_follow_up_at.isnot(None),
            Deal.next_follow_up_at <= horizon,
            Deal.closed_at.is_(None),
        )
        .limit(500)
        .all()
    )
    for deal in deal_rows:
        if not _follow_up_enabled(db, deal.business_id):
            continue
        key = f"follow_up:{deal.next_follow_up_at.isoformat()}"
        if _already_sent(db, deal.business_id, "deal", deal.id, key):
            continue
        target = _resolve_target_user_id(db, deal.business_id, deal.assigned_to_user_id)
        ok = _notify(
            db,
            user_id=target,
            event_key="crm.follow_up_due",
            title="یادآوری پیگیری فرصت فروش",
            message=f"زمان پیگیری فرصت فروش «{deal.title}» فرا رسیده است.",
            business_id=deal.business_id,
            entity_type="deal",
            entity_id=deal.id,
        )
        _mark_sent(db, deal.business_id, "deal", deal.id, key)
        if ok:
            stats["task_overdue"] += 0
            stats["follow_up"] += 1

    # --- وظایف سررسید گذشته ---
    task_rows = (
        db.query(CrmActivity)
        .filter(
            CrmActivity.is_task.is_(True),
            CrmActivity.status == "open",
            CrmActivity.due_at.isnot(None),
            CrmActivity.due_at < now,
        )
        .limit(500)
        .all()
    )
    for task in task_rows:
        if not _follow_up_enabled(db, task.business_id):
            continue
        key = f"task_overdue:{task.due_at.isoformat()}"
        if _already_sent(db, task.business_id, "activity", task.id, key):
            continue
        target = _resolve_target_user_id(db, task.business_id, task.assigned_to_user_id or task.created_by_user_id)
        ok = _notify(
            db,
            user_id=target,
            event_key="crm.task_overdue",
            title="وظیفه سررسید گذشته",
            message=f"وظیفه «{task.subject or task.code}» از موعد گذشته است.",
            business_id=task.business_id,
            entity_type="activity",
            entity_id=task.id,
        )
        _mark_sent(db, task.business_id, "activity", task.id, key)
        if ok:
            stats["task_overdue"] += 1

    # --- نقض SLA سرنخ (اولین تماس انجام نشده) ---
    sla_rows = (
        db.query(Lead)
        .filter(
            Lead.sla_due_at.isnot(None),
            Lead.sla_due_at < now,
            Lead.first_touched_at.is_(None),
            Lead.person_id.is_(None),
        )
        .limit(500)
        .all()
    )
    for lead in sla_rows:
        if not _follow_up_enabled(db, lead.business_id):
            continue
        key = f"sla_breach:{lead.sla_due_at.isoformat()}"
        if _already_sent(db, lead.business_id, "lead", lead.id, key):
            continue
        target = _resolve_target_user_id(db, lead.business_id, lead.assigned_to_user_id)
        ok = _notify(
            db,
            user_id=target,
            event_key="crm.lead_sla_breach",
            title="نقض SLA سرنخ",
            message=f"مهلت اولین تماس با سرنخ «{lead.name}» نقض شده است.",
            business_id=lead.business_id,
            entity_type="lead",
            entity_id=lead.id,
        )
        _mark_sent(db, lead.business_id, "lead", lead.id, key)
        if ok:
            stats["sla_breach"] += 1

    try:
        db.commit()
    except Exception:
        db.rollback()
    return stats


def flag_stale_deals(db: Session) -> Dict[str, int]:
    """اعلان برای فرصت‌های بازی که مدت طولانی در یک مرحله راکد مانده‌اند."""
    now = datetime.utcnow()
    stats = {"stale": 0}
    # کش تنظیمات هر کسب‌وکار برای اجتناب از کوئری تکراری
    settings_by_biz: Dict[int, BusinessCrmSettings] = {}

    deals = (
        db.query(Deal)
        .filter(Deal.closed_at.is_(None))
        .limit(1000)
        .all()
    )
    for deal in deals:
        try:
            settings = settings_by_biz.get(deal.business_id)
            if settings is None:
                settings = _get_settings(db, deal.business_id)
                settings_by_biz[deal.business_id] = settings
            if not settings.follow_up_notify_enabled:
                continue
            stale_days = int(settings.stale_deal_days or 0)
            if stale_days <= 0:
                continue
            reference = deal.stage_entered_at or deal.updated_at or deal.created_at
            if not reference:
                continue
            if (now - reference).days < stale_days:
                continue
            # کلید dedup بر اساس مرحله فعلی تا در هر مرحله فقط یک‌بار اعلان شود
            key = f"deal_stale:{deal.stage_id}"
            if _already_sent(db, deal.business_id, "deal", deal.id, key):
                continue
            target = _resolve_target_user_id(db, deal.business_id, deal.assigned_to_user_id)
            ok = _notify(
                db,
                user_id=target,
                event_key="crm.deal_stale",
                title="فرصت فروش راکد",
                message=f"فرصت فروش «{deal.title}» بیش از {stale_days} روز در یک مرحله باقی مانده است.",
                business_id=deal.business_id,
                entity_type="deal",
                entity_id=deal.id,
            )
            _mark_sent(db, deal.business_id, "deal", deal.id, key)
            if ok:
                stats["stale"] += 1
        except Exception:
            logger.exception("flag_stale_deals deal=%s failed", deal.id)

    try:
        db.commit()
    except Exception:
        db.rollback()
    return stats
