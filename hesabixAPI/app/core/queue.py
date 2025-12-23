"""
Queue Service با استفاده از RQ (Redis Queue)
برای مدیریت background jobs
"""

from __future__ import annotations

import json
import logging
from typing import Any, Dict, Optional, Callable
from datetime import timedelta

import rq
from rq import Queue, Worker
from rq.job import Job
from redis import Redis

from app.core.cache import get_redis_client
from app.core.settings import get_settings

logger = logging.getLogger(__name__)

# Queue names
QUEUE_DEFAULT = "default"
QUEUE_HIGH_PRIORITY = "high"
QUEUE_LOW_PRIORITY = "low"
QUEUE_EMAIL = "email"
QUEUE_REPORTS = "reports"
QUEUE_EXPORTS = "exports"
QUEUE_TAX = "tax"  # Queue مخصوص عملیات مالیاتی


def get_redis_connection() -> Optional[Redis]:
    """دریافت Redis connection برای RQ"""
    client = get_redis_client()
    if client is None:
        return None
    
    # RQ نیاز به Redis client بدون decode_responses دارد
    settings = get_settings()
    
    try:
        from adapters.db.session import get_db
        from app.services.system_settings_service import get_redis_configuration
        db_gen = get_db()
        db = next(db_gen)
        try:
            redis_config = get_redis_configuration(db)
            redis_enabled = redis_config.get('enabled', False)
            redis_host = redis_config.get('host', 'localhost')
            redis_port = redis_config.get('port', 6379)
            redis_db = redis_config.get('db', 0)
            redis_password = redis_config.get('password')
        finally:
            db.close()
    except Exception:
        redis_enabled = getattr(settings, 'redis_enabled', False)
        redis_host = getattr(settings, 'redis_host', 'localhost')
        redis_port = getattr(settings, 'redis_port', 6379)
        redis_db = getattr(settings, 'redis_db', 0)
        redis_password = getattr(settings, 'redis_password', None)
    
    if not redis_enabled:
        return None
    
    try:
        # RQ نیاز به Redis بدون decode_responses دارد
        redis_conn = Redis(
            host=redis_host,
            port=redis_port,
            db=redis_db,
            password=redis_password,
            decode_responses=False,  # RQ نیاز به bytes دارد
            socket_connect_timeout=2,
            socket_timeout=2,
            retry_on_timeout=True,
            health_check_interval=30
        )
        redis_conn.ping()
        return redis_conn
    except Exception as e:
        logger.warning(f"Failed to create Redis connection for RQ: {e}")
        return None


def get_queue(name: str = QUEUE_DEFAULT) -> Optional[Queue]:
    """دریافت queue با نام مشخص"""
    redis_conn = get_redis_connection()
    if redis_conn is None:
        return None
    return Queue(name, connection=redis_conn)


class QueueService:
    """سرویس مدیریت Queue"""
    
    def __init__(self):
        self.redis_conn = get_redis_connection()
        self.enabled = self.redis_conn is not None
    
    def enqueue(
        self,
        func: Callable,
        *args,
        queue_name: str = QUEUE_DEFAULT,
        timeout: int = 300,
        result_ttl: int = 3600,
        job_id: Optional[str] = None,
        **kwargs
    ) -> Optional[Job]:
        """
        اضافه کردن job به queue
        
        Args:
            func: تابعی که باید اجرا شود
            *args: آرگومان‌های positional
            queue_name: نام queue
            timeout: حداکثر زمان اجرا (ثانیه)
            result_ttl: زمان نگهداری نتیجه (ثانیه)
            job_id: شناسه job (اختیاری)
            **kwargs: آرگومان‌های keyword
        
        Returns:
            Job object یا None در صورت خطا
        """
        if not self.enabled:
            logger.warning("Queue service is disabled (Redis not available)")
            return None
        
        try:
            queue = get_queue(queue_name)
            if queue is None:
                return None
            
            job = queue.enqueue(
                func,
                *args,
                job_id=job_id,
                timeout=timeout,
                result_ttl=result_ttl,
                **kwargs
            )
            logger.info(f"Job {job.id} enqueued to {queue_name} queue")
            return job
        except Exception as e:
            logger.error(f"Error enqueueing job: {e}", exc_info=True)
            return None
    
    def get_job(self, job_id: str) -> Optional[Job]:
        """دریافت job با شناسه"""
        if not self.enabled:
            return None
        
        try:
            return Job.fetch(job_id, connection=self.redis_conn)
        except Exception as e:
            logger.warning(f"Error fetching job {job_id}: {e}")
            return None
    
    def get_job_status(self, job_id: str) -> Optional[Dict[str, Any]]:
        """دریافت وضعیت job به صورت dictionary"""
        job = self.get_job(job_id)
        if job is None:
            return None
        
        try:
            status = {
                "id": job.id,
                "state": job.get_status(),
                "created_at": job.created_at.isoformat() if job.created_at else None,
                "started_at": job.started_at.isoformat() if job.started_at else None,
                "ended_at": job.ended_at.isoformat() if job.ended_at else None,
                "result": None,
                "error": None,
                "updated_at": (job.ended_at or job.started_at or job.created_at).isoformat() if (job.ended_at or job.started_at or job.created_at) else None,
            }
            
            # اضافه کردن نتیجه یا خطا
            if job.is_finished:
                try:
                    status["result"] = job.result
                except Exception:
                    pass
            elif job.is_failed:
                try:
                    status["error"] = str(job.exc_info) if job.exc_info else "Unknown error"
                except Exception:
                    pass
            
            # اضافه کردن metadata اگر وجود دارد
            if job.meta:
                status["meta"] = job.meta
            
            return status
        except Exception as e:
            logger.error(f"Error getting job status {job_id}: {e}", exc_info=True)
            return None
    
    def cancel_job(self, job_id: str) -> bool:
        """لغو job"""
        job = self.get_job(job_id)
        if job is None:
            return False
        
        try:
            job.cancel()
            logger.info(f"Job {job_id} cancelled")
            return True
        except Exception as e:
            logger.error(f"Error cancelling job {job_id}: {e}", exc_info=True)
            return False
    
    def delete_job(self, job_id: str) -> bool:
        """حذف job"""
        job = self.get_job(job_id)
        if job is None:
            return False
        
        try:
            job.delete()
            logger.info(f"Job {job_id} deleted")
            return True
        except Exception as e:
            logger.error(f"Error deleting job {job_id}: {e}", exc_info=True)
            return False
    
    def get_queue_length(self, queue_name: str = QUEUE_DEFAULT) -> int:
        """دریافت تعداد jobs در queue"""
        queue = get_queue(queue_name)
        if queue is None:
            return 0
        return len(queue)
    
    def get_failed_jobs(self, limit: int = 10) -> list[Dict[str, Any]]:
        """دریافت لیست jobs ناموفق"""
        if not self.enabled:
            return []
        
        try:
            failed_registry = rq.registry.FailedJobRegistry(queue=Queue(connection=self.redis_conn))
            job_ids = failed_registry.get_job_ids(0, limit - 1)
            jobs = []
            for job_id in job_ids:
                status = self.get_job_status(job_id)
                if status:
                    jobs.append(status)
            return jobs
        except Exception as e:
            logger.error(f"Error getting failed jobs: {e}", exc_info=True)
            return []


_queue_service: Optional[QueueService] = None


def get_queue_service() -> QueueService:
    """دریافت instance از QueueService"""
    global _queue_service
    if _queue_service is None:
        _queue_service = QueueService()
    return _queue_service

