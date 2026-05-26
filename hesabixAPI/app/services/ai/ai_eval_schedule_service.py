"""
زمان‌بندی و اجرای خودکار ارزیابی AI.
"""
from __future__ import annotations

import logging
import os
from datetime import datetime
from typing import Any, Dict, Optional, Set, Tuple

import pytz
from croniter import croniter
from sqlalchemy.orm import Session

from adapters.db.models.ai_eval_schedule import AIEvalSchedule
from adapters.db.models.user import User
from app.core.auth_dependency import AuthContext
from app.services.ai.ai_eval_service import run_eval_suite

logger = logging.getLogger(__name__)

_schedule_fired: Set[str] = set()


def _prune_fired() -> None:
    global _schedule_fired
    if len(_schedule_fired) > 500:
        _schedule_fired = set(list(_schedule_fired)[-200:])


def get_schedule(db: Session) -> AIEvalSchedule:
    row = db.query(AIEvalSchedule).filter(AIEvalSchedule.id == 1).first()
    if not row:
        row = AIEvalSchedule(id=1, enabled=False)
        db.add(row)
        db.commit()
        db.refresh(row)
    return row


def schedule_to_dict(row: AIEvalSchedule) -> Dict[str, Any]:
    return {
        "id": row.id,
        "enabled": row.enabled,
        "cron_expression": row.cron_expression,
        "timezone": row.timezone,
        "business_id": row.business_id,
        "min_pass_rate": row.min_pass_rate,
        "last_run_id": row.last_run_id,
        "last_run_at": row.last_run_at.isoformat() if row.last_run_at else None,
        "last_pass_rate": row.last_pass_rate,
        "updated_at": row.updated_at.isoformat() if row.updated_at else None,
    }


def update_schedule(db: Session, data: Dict[str, Any]) -> AIEvalSchedule:
    row = get_schedule(db)
    for key in ("enabled", "cron_expression", "timezone", "business_id", "min_pass_rate"):
        if key in data and data[key] is not None:
            setattr(row, key, data[key])
    row.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(row)
    return row


def _cron_should_fire(schedule: str, timezone_name: str, now_utc: datetime) -> Tuple[bool, str]:
    if not schedule or not str(schedule).strip():
        return False, ""
    try:
        tz = pytz.timezone(timezone_name or "Asia/Tehran")
    except Exception:
        tz = pytz.UTC
    if now_utc.tzinfo is None:
        now_utc = now_utc.replace(tzinfo=pytz.UTC)
    local_naive = now_utc.astimezone(tz).replace(tzinfo=None)
    try:
        itr = croniter(str(schedule).strip(), local_naive)
        prev_fire = itr.get_prev(datetime)
    except Exception as exc:
        logger.warning("AI eval cron parse failed: %s", exc)
        return False, ""
    delta = (local_naive - prev_fire.replace(tzinfo=None)).total_seconds()
    if 0 <= delta < 90:
        return True, prev_fire.strftime("%Y%m%d%H%M")
    return False, ""


def _scheduler_auth_context(db: Session) -> Optional[AuthContext]:
    user_id = os.getenv("HESABIX_AI_EVAL_USER_ID")
    user: Optional[User] = None
    if user_id:
        try:
            user = db.query(User).filter(User.id == int(user_id)).first()
        except ValueError:
            pass
    if not user:
        users = db.query(User).limit(200).all()
        for u in users:
            perms = u.app_permissions if isinstance(u.app_permissions, dict) else {}
            if perms.get("superadmin"):
                user = u
                break
    if not user:
        logger.warning("No user for AI eval scheduler")
        return None
    return AuthContext(user=user, api_key_id=0, db=db, business_id=None)


async def run_scheduled_eval_if_due(db: Session, now_utc: Optional[datetime] = None) -> Dict[str, Any]:
    """یک tick؛ در صورت رسیدن cron ارزیابی را اجرا می‌کند."""
    global _schedule_fired
    _prune_fired()
    now_utc = now_utc or datetime.utcnow().replace(tzinfo=pytz.UTC)
    sched = get_schedule(db)
    if not sched.enabled:
        return {"fired": False, "reason": "disabled"}

    ok, slot_key = _cron_should_fire(sched.cron_expression, sched.timezone, now_utc)
    if not ok or not slot_key:
        return {"fired": False, "reason": "not_due"}
    if slot_key in _schedule_fired:
        return {"fired": False, "reason": "already_fired"}
    _schedule_fired.add(slot_key)

    ctx = _scheduler_auth_context(db)
    if not ctx:
        return {"fired": False, "reason": "no_scheduler_user"}

    try:
        result = await run_eval_suite(db, ctx, business_id=sched.business_id)
    except Exception as exc:
        logger.error("Scheduled AI eval failed: %s", exc, exc_info=True)
        return {"fired": False, "reason": "error", "error": str(exc)}

    run_info = result.get("run") or {}
    total = int(run_info.get("total_cases") or 0)
    passed = int(run_info.get("passed_cases") or 0)
    pass_rate = round((passed / total) * 100) if total else 0

    sched.last_run_id = run_info.get("id")
    sched.last_run_at = datetime.utcnow()
    sched.last_pass_rate = pass_rate
    sched.updated_at = datetime.utcnow()
    db.commit()

    below_threshold = total > 0 and pass_rate < int(sched.min_pass_rate or 70)
    if below_threshold:
        logger.warning(
            "AI eval scheduled run below threshold: %s%% < %s%% (run_id=%s)",
            pass_rate,
            sched.min_pass_rate,
            sched.last_run_id,
        )

    return {
        "fired": True,
        "run_id": sched.last_run_id,
        "pass_rate": pass_rate,
        "below_threshold": below_threshold,
    }
