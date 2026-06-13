"""
زمان‌بندی و اجرای خودکار task های AI برای کسب‌وکار.
"""
from __future__ import annotations

import logging
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.db.seed_data.ai_default_prompts import SCHEDULED_TASK_PROMPT_KEYS
from app.services.ai.prompt_service import get_prompt_by_key

logger = logging.getLogger(__name__)

BUILT_IN_TASKS: List[Dict[str, Any]] = [
    {
        "id": "weekly_sales_report",
        "name": "گزارش فروش هفتگی",
        "description": "هر شنبه صبح خلاصه فروش هفته گذشته تهیه می‌شود.",
        "cron": "0 8 * * 6",
        "category": "financial",
        "enabled_by_default": True,
    },
    {
        "id": "overdue_invoices",
        "name": "فاکتورهای پرداخت‌نشده",
        "description": "هر روز صبح فاکتورهای معوق بررسی می‌شوند.",
        "cron": "0 9 * * *",
        "category": "financial",
        "enabled_by_default": False,
    },
    {
        "id": "low_stock_alert",
        "name": "هشدار موجودی کم",
        "description": "هر روز صبح موجودی انبار بررسی می‌شود.",
        "cron": "0 8 * * *",
        "category": "warehouse",
        "enabled_by_default": False,
    },
    {
        "id": "monthly_summary",
        "name": "خلاصه ماهانه",
        "description": "اول هر ماه خلاصه ماه گذشته تهیه می‌شود.",
        "cron": "0 8 1 * *",
        "category": "financial",
        "enabled_by_default": False,
    },
]


def _resolve_task_prompt(db: Optional[Session], task_id: str) -> str:
    prompt_key = SCHEDULED_TASK_PROMPT_KEYS.get(task_id)
    if not prompt_key:
        return ""
    return get_prompt_by_key(db, prompt_key)


def _hydrate_task(task: Dict[str, Any], db: Optional[Session] = None) -> Dict[str, Any]:
    hydrated = dict(task)
    hydrated["prompt"] = _resolve_task_prompt(db, hydrated.get("id", ""))
    return hydrated


def get_built_in_tasks(db: Optional[Session] = None) -> List[Dict[str, Any]]:
    return [_hydrate_task(task, db) for task in BUILT_IN_TASKS]


def get_task_by_id(task_id: str, db: Optional[Session] = None) -> Optional[Dict[str, Any]]:
    for task in BUILT_IN_TASKS:
        if task["id"] == task_id:
            return _hydrate_task(task, db)
    return None


def should_task_run(task: Dict[str, Any], now: Optional[datetime] = None) -> bool:
    cron_expr = task.get("cron")
    if not cron_expr:
        return False

    now = now or datetime.now()
    try:
        from croniter import croniter
        itr = croniter(cron_expr, now)
        prev = itr.get_prev(datetime)
        delta = (now - prev).total_seconds()
        return 0 <= delta < 90
    except Exception as exc:
        logger.warning("Cron parse error for task %s: %s", task.get("id"), exc)
        return False


async def run_scheduled_task(
    db: Session,
    task: Dict[str, Any],
    business_id: int,
    ai_service,
    session_id: Optional[int] = None,
) -> Dict[str, Any]:
    task_id = task.get("id", "unknown")
    prompt = task.get("prompt") or _resolve_task_prompt(db, task_id)

    if not prompt:
        return {"task_id": task_id, "success": False, "reason": "no_prompt"}

    try:
        response = await ai_service.chat_completion(
            messages=[{"role": "user", "content": prompt}],
            use_function_calling=True,
            session_business_id=business_id,
            session_id=session_id,
            max_tokens_override=2000,
        )
        content = (response.get("message") or {}).get("content", "")
        return {
            "task_id": task_id,
            "success": True,
            "content": content,
            "ran_at": datetime.utcnow().isoformat(),
        }
    except Exception as exc:
        logger.error("Scheduled task %s failed: %s", task_id, exc, exc_info=True)
        return {
            "task_id": task_id,
            "success": False,
            "error": str(exc),
            "ran_at": datetime.utcnow().isoformat(),
        }
