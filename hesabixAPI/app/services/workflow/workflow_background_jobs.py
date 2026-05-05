"""
Jobهای پس‌زمینه برای ورک‌فلو: زمان‌بندی (cron) و یادآوری سررسید چک.
"""

from __future__ import annotations

import logging
from datetime import date, datetime
from typing import Dict, Optional, Set, Tuple

import pytz
from croniter import croniter
from sqlalchemy import select, or_
from sqlalchemy.orm import Session

from adapters.db.models.check import Check, CheckStatus
from adapters.db.models.workflow import Workflow, WorkflowStatus
from app.services.workflow.schedule_cron_resolution import resolve_schedule_config_to_cron
from app.services.workflow.workflow_trigger_service import (
    fire_check_due_workflow_triggers,
    run_scheduled_workflow_fire,
)

logger = logging.getLogger(__name__)

_scheduled_fired: Set[Tuple[int, str]] = set()
_check_due_fired: Set[Tuple[int, str]] = set()


def _prune_fired_sets() -> None:
    global _scheduled_fired, _check_due_fired
    if len(_scheduled_fired) > 5000:
        _scheduled_fired = set(list(_scheduled_fired)[-2000:])
    if len(_check_due_fired) > 5000:
        _check_due_fired = set(list(_check_due_fired)[-2000:])


def _cron_should_fire_now(schedule: str, timezone_name: str, now_utc: datetime) -> Tuple[bool, str]:
    """
    آیا این دقیقه (به‌زمان محلی تریگر) زمان اجرای cron است؟
    برمی‌گرداند: (bool, dedup_key)

    dedup_key باید از **اسلات cron** (prev_fire) باشد نه از ساعت فعلی؛
    وگرنه با پنجرهٔ ۹۰ ثانیه‌ای، یک اسلات مشترک در دو دقیقهٔ متوالی wall-clock
    دوبار اجرا می‌شد (minute_key فرق می‌کرد و مجموعهٔ in-memory مانع تکرار نمی‌شد).
    """
    if not schedule or not str(schedule).strip():
        return False, ""
    try:
        tz = pytz.timezone(timezone_name or "Asia/Tehran")
    except Exception:
        tz = pytz.UTC
    if now_utc.tzinfo is None:
        now_utc = now_utc.replace(tzinfo=pytz.UTC)
    local_now = now_utc.astimezone(tz)
    local_naive = local_now.replace(tzinfo=None)
    try:
        itr = croniter(str(schedule).strip(), local_naive)
        prev_fire = itr.get_prev(datetime)
    except Exception as e:
        logger.warning("croniter parse failed schedule=%r: %s", schedule, e)
        return False, ""
    if not isinstance(prev_fire, datetime):
        return False, ""
    delta = (local_naive - prev_fire.replace(tzinfo=None)).total_seconds()
    if 0 <= delta < 90:
        # دقیقهٔ اسلات برنامه‌ریزی‌شده (۵ فیلد cron = وضوح دقیقه)
        slot_key = prev_fire.replace(tzinfo=None).strftime("%Y%m%d%H%M")
        return True, slot_key
    return False, ""


def _tick_scheduled_workflows(db: Session, now_utc: Optional[datetime] = None) -> int:
    now_utc = now_utc or datetime.utcnow().replace(tzinfo=pytz.UTC)
    stmt = select(Workflow).where(Workflow.status == WorkflowStatus.ACTIVE)
    workflows = list(db.execute(stmt).scalars().all())
    fired = 0
    for wf in workflows:
        data = wf.workflow_data or {}
        nodes = data.get("nodes") or []
        trigger_node = None
        for n in nodes:
            if not isinstance(n, dict):
                continue
            if n.get("type") != "trigger":
                continue
            cfg = n.get("config") or {}
            if cfg.get("trigger_type") == "scheduled":
                trigger_node = n
                break
        if not trigger_node:
            continue
        cfg = trigger_node.get("config") or {}
        schedule = resolve_schedule_config_to_cron(cfg if isinstance(cfg, dict) else {})
        tz_name = cfg.get("timezone") or "Asia/Tehran"
        ok, minute_key = _cron_should_fire_now(str(schedule or ""), tz_name, now_utc)
        if not ok or not minute_key:
            continue
        dedup = (int(wf.id), minute_key)
        if dedup in _scheduled_fired:
            continue
        _scheduled_fired.add(dedup)
        fired += run_scheduled_workflow_fire(db, wf.business_id, wf.id, user_id=None)
    return fired


def _tick_check_due(db: Session, today: Optional[date] = None) -> int:
    today = today or date.today()
    terminal = {
        CheckStatus.CLEARED,
        CheckStatus.CANCELLED,
        CheckStatus.RETURNED,
        CheckStatus.BOUNCED,
    }
    stmt = select(Check).where(
        or_(Check.status.is_(None), ~Check.status.in_(list(terminal)))
    )
    checks = list(db.execute(stmt).scalars().all())
    fired = 0
    for ch in checks:
        dk = (int(ch.id), today.isoformat())
        if dk in _check_due_fired:
            continue
        due = ch.due_date
        due_d = due.date() if hasattr(due, "date") else due
        if isinstance(due_d, datetime):
            due_d = due_d.date()
        days_until = (due_d - today).days
        if days_until > 366:
            continue
        _check_due_fired.add(dk)
        try:
            fired += fire_check_due_workflow_triggers(db, ch.business_id, ch.id, user_id=None)
        except Exception as e:
            logger.error("check due trigger failed check_id=%s: %s", ch.id, e, exc_info=True)
    return fired


def workflow_automation_tick_once() -> Dict[str, int]:
    """یک بار اسکن زمان‌بندی و چک‌ها (برای job یا تست)."""
    from adapters.db.session import get_db_session

    _prune_fired_sets()
    out = {"scheduled_fires": 0, "check_due_triggers": 0}
    with get_db_session() as db:
        try:
            out["scheduled_fires"] = _tick_scheduled_workflows(db)
        except Exception as e:
            logger.error("scheduled workflow tick failed: %s", e, exc_info=True)
        try:
            out["check_due_triggers"] = _tick_check_due(db)
        except Exception as e:
            logger.error("check due tick failed: %s", e, exc_info=True)
        try:
            db.commit()
        except Exception:
            db.rollback()
    return out


async def workflow_automation_background_loop(interval_seconds: int = 60) -> None:
    import asyncio

    while True:
        try:
            await asyncio.to_thread(workflow_automation_tick_once)
        except Exception:
            logger.exception("workflow_automation_background_loop tick error")
        await asyncio.sleep(max(30, int(interval_seconds)))
