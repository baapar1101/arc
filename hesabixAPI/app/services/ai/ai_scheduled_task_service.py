"""
زمان‌بندی و اجرای خودکار task های AI برای کسب‌وکار.

مثال‌های پشتیبانی‌شده:
  - weekly_sales_report: گزارش فروش هفتگی
  - overdue_invoices: یادآوری فاکتورهای معوق
  - low_stock_alert: هشدار موجودی کم
  - monthly_summary: خلاصه ماهانه

هر task بر اساس یک cron expression اجرا می‌شود و نتیجه را
در session هوش مصنوعی کاربر ذخیره می‌کند (یا notification می‌فرستد).
"""
from __future__ import annotations

import logging
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)

# ---- Task definitions ----

BUILT_IN_TASKS: List[Dict[str, Any]] = [
    {
        "id": "weekly_sales_report",
        "name": "گزارش فروش هفتگی",
        "description": "هر شنبه صبح خلاصه فروش هفته گذشته تهیه می‌شود.",
        "cron": "0 8 * * 6",  # شنبه ساعت ۸
        "prompt": (
            "گزارش جامع فروش هفته گذشته را تهیه کن: "
            "تعداد فاکتور، مجموع درآمد، بهترین محصولات، "
            "مشتریان فعال و مقایسه با هفته قبل از آن."
        ),
        "category": "financial",
        "enabled_by_default": True,
    },
    {
        "id": "overdue_invoices",
        "name": "فاکتورهای پرداخت‌نشده",
        "description": "هر روز صبح فاکتورهای معوق بررسی می‌شوند.",
        "cron": "0 9 * * *",  # هر روز ساعت ۹
        "prompt": (
            "لیست فاکتورهای پرداخت‌نشده و معوق را بررسی کن "
            "و مشتریانی که بیش از ۳۰ روز بدهی دارند را مشخص کن."
        ),
        "category": "financial",
        "enabled_by_default": False,
    },
    {
        "id": "low_stock_alert",
        "name": "هشدار موجودی کم",
        "description": "هر روز صبح موجودی انبار بررسی می‌شود.",
        "cron": "0 8 * * *",
        "prompt": (
            "موجودی انبار را بررسی کن و کالاهایی که موجودی آن‌ها "
            "کمتر از حد هشدار است را فهرست کن."
        ),
        "category": "warehouse",
        "enabled_by_default": False,
    },
    {
        "id": "monthly_summary",
        "name": "خلاصه ماهانه",
        "description": "اول هر ماه خلاصه ماه گذشته تهیه می‌شود.",
        "cron": "0 8 1 * *",  # اول هر ماه ساعت ۸
        "prompt": (
            "خلاصه جامع ماه گذشته را تهیه کن: "
            "فروش، هزینه‌ها، سود خالص، رشد نسبت به ماه قبل، "
            "و مهم‌ترین رویدادهای مالی."
        ),
        "category": "financial",
        "enabled_by_default": False,
    },
]


def get_built_in_tasks() -> List[Dict[str, Any]]:
    """لیست task های پیش‌فرض."""
    return [dict(t) for t in BUILT_IN_TASKS]


def get_task_by_id(task_id: str) -> Optional[Dict[str, Any]]:
    for t in BUILT_IN_TASKS:
        if t["id"] == task_id:
            return dict(t)
    return None


def should_task_run(task: Dict[str, Any], now: Optional[datetime] = None) -> bool:
    """
    بررسی اینکه آیا task باید در لحظه فعلی اجرا شود.
    از croniter استفاده می‌کند.
    """
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
    """
    اجرای یک scheduled task و برگرداندن نتیجه.
    نتیجه می‌تواند به یک AI session ذخیره شود.
    """
    task_id = task.get("id", "unknown")
    prompt = task.get("prompt", "")

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
