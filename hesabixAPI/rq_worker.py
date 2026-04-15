#!/usr/bin/env python3
"""
RQ Worker برای اجرای background jobs
"""

import sys
import os

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from rq import Worker
from app.core.queue import (
    get_redis_connection,
    is_redis_enabled_in_configuration,
    QUEUE_DEFAULT,
    QUEUE_HIGH_PRIORITY,
    QUEUE_LOW_PRIORITY,
    QUEUE_EMAIL,
    QUEUE_REPORTS,
    QUEUE_EXPORTS,
)

if __name__ == "__main__":
    # اگر مدیر Redis را در تنظیمات کل سیستم خاموش کرده باشد، با کد خروج ۰ متوقف می‌شویم
    # تا با Restart=on-failure در systemd حلقهٔ بی‌پایان ری‌استارت ایجاد نشود.
    if not is_redis_enabled_in_configuration():
        print(
            "RQ worker: Redis is disabled in system settings. "
            "Background queue jobs are skipped; API falls back to DB/in-process where implemented. Exiting."
        )
        print(
            "کارگر RQ: Redis در تنظیمات سیستم غیرفعال است؛ صف پس‌زمینه اجرا نمی‌شود. خروج عادی."
        )
        sys.exit(0)

    redis_conn = get_redis_connection()

    if redis_conn is None:
        print(
            "Error: Redis is enabled but connection failed. "
            "Check host/port/firewall and Redis service, then retry."
        )
        sys.exit(1)
    
    # تعریف queues به ترتیب اولویت
    queues = [
        QUEUE_HIGH_PRIORITY,
        QUEUE_DEFAULT,
        QUEUE_EMAIL,
        QUEUE_REPORTS,
        QUEUE_EXPORTS,
        QUEUE_LOW_PRIORITY,
    ]
    
    print(f"Starting RQ worker for queues: {', '.join(queues)}")
    
    # در RQ 2.x، Connection دیگر لازم نیست
    worker = Worker(queues, connection=redis_conn)
    worker.work()

