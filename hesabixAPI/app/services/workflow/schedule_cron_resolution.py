"""
تبدیل تنظیمات «زمان‌بندی ساده» به رشتهٔ کرون ۵ بخشی (دقیقه ساعت روز ماه روزهفته).
حالت پیشرفته (cron دستی) بدون تغییر عبور داده می‌شود.
"""

from __future__ import annotations

import re
from typing import Any, Dict, Optional


def _parse_hhmm(value: Any) -> Optional[tuple[int, int]]:
    if value is None:
        return None
    s = str(value).strip()
    m = re.match(r"^\s*(\d{1,2})\s*:\s*(\d{1,2})\s*$", s)
    if not m:
        return None
    h, mn = int(m.group(1)), int(m.group(2))
    if 0 <= h <= 23 and 0 <= mn <= 59:
        return mn, h
    return None


def resolve_schedule_config_to_cron(config: Dict[str, Any]) -> str:
    """
    از config نود تریگر scheduled یک عبارت cron معتبر برمی‌گرداند.
    - اگر schedule_mode == cron (یا خالی و فقط schedule پر است): همان فیلد schedule.
    - اگر schedule_mode == simple: از فیلدهای simple_* ساخته می‌شود.
    """
    cfg = config or {}
    mode = str(cfg.get("schedule_mode") or "").strip().lower()
    raw_schedule = str(cfg.get("schedule") or "").strip()

    # سازگاری عقب‌رو: ورک‌فلوهای قدیمی بدون schedule_mode
    if mode in ("", "cron", "advanced_cron"):
        if raw_schedule:
            return raw_schedule
        if mode in ("cron", "advanced_cron"):
            return ""
        # بدون mode و بدون کرون: فقط اگر فیلدهای حالت ساده پر شده باشد
        if (
            str(cfg.get("schedule_mode") or "").strip().lower() == "simple"
            or cfg.get("simple_repeat")
            or cfg.get("simple_time")
            or cfg.get("simple_interval") is not None
        ):
            mode = "simple"
        else:
            return ""

    if mode != "simple":
        return raw_schedule or ""

    repeat = str(cfg.get("simple_repeat") or "daily").strip().lower()
    t = _parse_hhmm(cfg.get("simple_time"))
    if t is None:
        t = _parse_hhmm("08:00")
    if t is None:
        return ""
    minute, hour = t

    if repeat == "daily":
        return f"{minute} {hour} * * *"

    if repeat == "weekly":
        try:
            dow = int(cfg.get("simple_weekday", 0))
        except (TypeError, ValueError):
            dow = 0
        dow = max(0, min(6, dow))
        return f"{minute} {hour} * * {dow}"

    if repeat == "every_minutes":
        try:
            n = int(cfg.get("simple_interval") or 15)
        except (TypeError, ValueError):
            n = 15
        n = max(1, min(59, n))
        return f"*/{n} * * * *"

    if repeat == "every_hours":
        try:
            n = int(cfg.get("simple_interval") or 1)
        except (TypeError, ValueError):
            n = 1
        n = max(1, min(23, n))
        return f"0 */{n} * * *"

    # پیش‌فرض: روزانه
    return f"{minute} {hour} * * *"


def schedule_config_is_valid(config: Dict[str, Any]) -> bool:
    """آیا برای اجرای زمان‌بندی حداقل یک کرون قابل محاسبه داریم؟"""
    return bool(resolve_schedule_config_to_cron(config or {}).strip())
