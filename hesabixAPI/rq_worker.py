#!/usr/bin/env python3
"""
RQ Worker برای اجرای background jobs
"""

import sys
import os

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from rq import Worker
from app.core.queue import get_redis_connection, QUEUE_DEFAULT, QUEUE_HIGH_PRIORITY, QUEUE_LOW_PRIORITY, QUEUE_EMAIL, QUEUE_REPORTS, QUEUE_EXPORTS

if __name__ == "__main__":
    redis_conn = get_redis_connection()
    
    if redis_conn is None:
        print("Error: Redis connection not available. Please check Redis configuration.")
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

