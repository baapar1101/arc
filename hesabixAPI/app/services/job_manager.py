from __future__ import annotations

import json
import threading
import time
import uuid
from dataclasses import dataclass, field
from typing import Any, Dict, Optional

from app.core.queue import get_queue_service, QueueService
from app.core.cache import get_cache
from adapters.db.session import get_db_session
from sqlalchemy import text


@dataclass
class JobStatus:
    id: str
    state: str = "queued"  # queued, running, succeeded, failed
    progress: int = 0
    message: str | None = None
    result: Dict[str, Any] | None = None
    error: str | None = None
    created_at: float = field(default_factory=lambda: time.time())
    updated_at: float = field(default_factory=lambda: time.time())

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "state": self.state,
            "progress": self.progress,
            "message": self.message,
            "result": self.result,
            "error": self.error,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
        }


class JobManager:
    _instance: "JobManager" | None = None
    _lock = threading.Lock()

    def __init__(self) -> None:
        self._jobs: Dict[str, JobStatus] = {}  # Fallback local memory
        self._jobs_lock = threading.Lock()
        self._queue_service: Optional[QueueService] = None
        self._cache = get_cache()
        self._redis_prefix = "job_manager:"

    @classmethod
    def instance(cls) -> "JobManager":
        with cls._lock:
            if cls._instance is None:
                cls._instance = JobManager()
            return cls._instance

    @property
    def queue_service(self) -> QueueService:
        """دریافت QueueService (lazy loading)"""
        if self._queue_service is None:
            self._queue_service = get_queue_service()
        return self._queue_service

    def create(self, message: str | None = None) -> str:
        """ایجاد job ID جدید"""
        import logging
        logger = logging.getLogger(__name__)
        
        job_id = str(uuid.uuid4())
        status = JobStatus(id=job_id, message=message or "Queued")
        
        # ذخیره در Redis اگر در دسترس باشد
        # بررسی مستقیم Redis connection (نه فقط cache.enabled)
        cache_enabled = False
        if self._cache:
            # اگر cache service وجود دارد، سعی می‌کنیم Redis را تست کنیم
            try:
                if hasattr(self._cache, 'client') and self._cache.client:
                    self._cache.client.ping()
                    cache_enabled = True
            except Exception:
                pass
        
        if cache_enabled:
            try:
                key = f"{self._redis_prefix}{job_id}"
                data = {
                    "id": status.id,
                    "state": status.state,
                    "progress": status.progress,
                    "message": status.message,
                    "result": status.result,
                    "error": status.error,
                    "created_at": status.created_at,
                    "updated_at": status.updated_at,
                }
                # TTL: 24 ساعت
                self._cache.set(key, json.dumps(data), ttl=86400)
                logger.info(f"[JOB_MANAGER] Created job {job_id} in Redis with message: {message or 'Queued'}")
            except Exception as e:
                logger.warning(f"[JOB_MANAGER] Failed to save job {job_id} to Redis: {e}, using local memory")
                with self._jobs_lock:
                    self._jobs[job_id] = status
        else:
            # Fallback: ذخیره در database
            try:
                with get_db_session() as db:
                    # استفاده از یک جدول ساده برای ذخیره jobs
                    db.execute(
                        text("""
                            CREATE TABLE IF NOT EXISTS job_statuses (
                                id VARCHAR(36) PRIMARY KEY,
                                state VARCHAR(20) NOT NULL,
                                progress INTEGER DEFAULT 0,
                                message TEXT,
                                result JSONB,
                                error TEXT,
                                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                            )
                        """)
                    )
                    db.execute(
                        text("""
                            INSERT INTO job_statuses (id, state, progress, message, result, error, created_at, updated_at)
                            VALUES (:id, :state, :progress, :message, :result, :error, to_timestamp(:created_at), to_timestamp(:updated_at))
                            ON CONFLICT (id) DO UPDATE SET
                                state = EXCLUDED.state,
                                progress = EXCLUDED.progress,
                                message = EXCLUDED.message,
                                result = EXCLUDED.result,
                                error = EXCLUDED.error,
                                updated_at = to_timestamp(:updated_at)
                        """),
                        {
                            "id": status.id,
                            "state": status.state,
                            "progress": status.progress,
                            "message": status.message,
                            "result": json.dumps(status.result) if status.result else None,
                            "error": status.error,
                            "created_at": status.created_at,
                            "updated_at": status.updated_at,
                        }
                    )
                    db.commit()
                logger.info(f"[JOB_MANAGER] Created job {job_id} in database (Redis not available)")
            except Exception as e:
                logger.warning(f"[JOB_MANAGER] Failed to save job {job_id} to database: {e}, using local memory")
                # Fallback به local memory
                with self._jobs_lock:
                    self._jobs[job_id] = status
                logger.info(f"[JOB_MANAGER] Created job {job_id} in local memory (database fallback failed)")
        
        return job_id

    def get(self, job_id: str) -> Optional[JobStatus]:
        """دریافت وضعیت job"""
        import logging
        logger = logging.getLogger(__name__)
        
        logger.info(f"[JOB_MANAGER] get() called for job_id: {job_id}, queue_service.enabled: {self.queue_service.enabled}")
        
        # ابتدا از queue service بررسی می‌کنیم
        if self.queue_service.enabled:
            logger.info(f"[JOB_MANAGER] Checking queue service for job {job_id}")
            queue_status = self.queue_service.get_job_status(job_id)
            if queue_status:
                logger.info(f"[JOB_MANAGER] Job {job_id} found in queue service via JobManager.get(), state: {queue_status.get('state')}")
                # تبدیل به JobStatus
                state_map = {
                    "queued": "queued",
                    "started": "running",
                    "finished": "succeeded",
                    "failed": "failed",
                    "deferred": "queued",
                    "scheduled": "queued",
                }
                queue_meta = queue_status.get("meta", {})
                status = JobStatus(
                    id=queue_status["id"],
                    state=state_map.get(queue_status["state"], "queued"),
                    message=queue_meta.get("message"),
                    result=queue_status.get("result"),
                    error=queue_status.get("error"),
                )
                if queue_status.get("created_at"):
                    from datetime import datetime
                    try:
                        created_str = queue_status["created_at"]
                        if isinstance(created_str, str):
                            created_dt = datetime.fromisoformat(created_str.replace("Z", "+00:00"))
                            status.created_at = created_dt.timestamp()
                    except Exception:
                        pass
                # استفاده از ended_at یا started_at برای updated_at
                updated_str = queue_status.get("ended_at") or queue_status.get("started_at") or queue_status.get("created_at")
                if updated_str:
                    from datetime import datetime
                    try:
                        if isinstance(updated_str, str):
                            updated_dt = datetime.fromisoformat(updated_str.replace("Z", "+00:00"))
                            status.updated_at = updated_dt.timestamp()
                    except Exception:
                        pass
                return status
            # اگر queue service enabled است اما job پیدا نشد، به memory-based jobs fallback می‌کنیم
            # چون ممکن است job در memory-based jobs باشد (مثل backup)
            logger.info(f"[JOB_MANAGER] Job {job_id} not found in queue service, checking memory-based jobs")
        else:
            logger.info(f"[JOB_MANAGER] Queue service not enabled, checking memory-based jobs directly")
        
        # Fallback به memory-based jobs (از Redis یا local memory)
        # ابتدا از Redis بررسی کن
        cache_enabled = False
        if self._cache:
            # بررسی مستقیم Redis connection
            try:
                if hasattr(self._cache, 'client') and self._cache.client:
                    self._cache.client.ping()
                    cache_enabled = True
            except Exception:
                pass
        
        if cache_enabled:
            try:
                key = f"{self._redis_prefix}{job_id}"
                data = self._cache.get(key)
                if data:
                    # cache.get() ممکن است dict یا string برگرداند
                    if isinstance(data, str):
                        data = json.loads(data)
                    elif not isinstance(data, dict):
                        logger.warning(f"[JOB_MANAGER] Unexpected data type from Redis for job {job_id}: {type(data)}")
                        data = None
                    
                    if data:
                        job = JobStatus(
                            id=data["id"],
                            state=data["state"],
                            progress=data.get("progress", 0),
                            message=data.get("message"),
                            result=data.get("result"),
                            error=data.get("error"),
                            created_at=data.get("created_at", time.time()),
                            updated_at=data.get("updated_at", time.time()),
                        )
                        logger.info(f"[JOB_MANAGER] Job {job_id} found in Redis, state: {job.state}, message: {job.message}, progress: {job.progress}")
                        return job
            except Exception as e:
                logger.warning(f"[JOB_MANAGER] Error reading job {job_id} from Redis: {e}", exc_info=True)
        
        # Fallback: بررسی database
        try:
            with get_db_session() as db:
                result = db.execute(
                    text("""
                        SELECT id, state, progress, message, result, error,
                               EXTRACT(EPOCH FROM created_at) as created_at,
                               EXTRACT(EPOCH FROM updated_at) as updated_at
                        FROM job_statuses
                        WHERE id = :job_id
                    """),
                    {"job_id": job_id}
                ).fetchone()
                
                if result:
                    # تبدیل Decimal به float برای timestamp
                    from decimal import Decimal
                    created_at = float(result.created_at) if result.created_at else time.time()
                    updated_at = float(result.updated_at) if result.updated_at else time.time()
                    
                    job = JobStatus(
                        id=result.id,
                        state=result.state,
                        progress=int(result.progress) if result.progress is not None else 0,
                        message=result.message,
                        result=json.loads(result.result) if result.result else None,
                        error=result.error,
                        created_at=created_at,
                        updated_at=updated_at,
                    )
                    logger.info(f"[JOB_MANAGER] Job {job_id} found in database, state: {job.state}, message: {job.message}, progress: {job.progress}")
                    return job
        except Exception as e:
            logger.warning(f"[JOB_MANAGER] Error reading job {job_id} from database: {e}")
        
        # Fallback به local memory
        with self._jobs_lock:
            job = self._jobs.get(job_id)
            if job:
                logger.info(f"[JOB_MANAGER] Job {job_id} found in local memory, state: {job.state}, message: {job.message}, progress: {job.progress}")
            else:
                logger.warning(f"[JOB_MANAGER] Job {job_id} not found in Redis, database, or local memory (total jobs in local memory: {len(self._jobs)})")
                # لیست job IDs موجود در memory را لاگ کن (برای debugging)
                if len(self._jobs) > 0:
                    job_ids = list(self._jobs.keys())[:10]  # فقط 10 تا اول
                    logger.info(f"[JOB_MANAGER] Available job IDs in local memory (first 10): {job_ids}")
            return job

    def start(self, job_id: str, message: str | None = None) -> None:
        st = self.get(job_id)
        if not st:
            return
        st.state = "running"
        st.message = message or "Running"
        st.updated_at = time.time()
        self._save_job(st)

    def update(self, job_id: str, progress: int, message: str | None = None) -> None:
        st = self.get(job_id)
        if not st:
            return
        st.progress = max(0, min(100, progress))
        if message is not None:
            st.message = message
        st.updated_at = time.time()
        self._save_job(st)

    def succeed(self, job_id: str, result: Dict[str, Any] | None = None, message: str | None = None) -> None:
        st = self.get(job_id)
        if not st:
            return
        st.state = "succeeded"
        st.progress = 100
        st.result = result
        if message is not None:
            st.message = message
        st.updated_at = time.time()
        self._save_job(st)

    def fail(self, job_id: str, error: str, message: str | None = None) -> None:
        st = self.get(job_id)
        if not st:
            return
        st.state = "failed"
        # اطمینان از اینکه error همیشه set شود
        st.error = error if error and error.strip() else "Job failed without error details"
        if message is not None:
            st.message = message
        st.updated_at = time.time()
        self._save_job(st)
    
    def _save_job(self, job: JobStatus) -> None:
        """ذخیره job در Redis یا local memory"""
        import logging
        logger = logging.getLogger(__name__)
        
        # بررسی مستقیم Redis connection
        cache_enabled = False
        if self._cache:
            try:
                if hasattr(self._cache, 'client') and self._cache.client:
                    self._cache.client.ping()
                    cache_enabled = True
            except Exception:
                pass
        
        if cache_enabled:
            try:
                key = f"{self._redis_prefix}{job.id}"
                data = {
                    "id": job.id,
                    "state": job.state,
                    "progress": job.progress,
                    "message": job.message,
                    "result": job.result,
                    "error": job.error,
                    "created_at": job.created_at,
                    "updated_at": job.updated_at,
                }
                # TTL: 24 ساعت
                self._cache.set(key, json.dumps(data), ttl=86400)
            except Exception as e:
                logger.warning(f"[JOB_MANAGER] Failed to save job {job.id} to Redis: {e}, using local memory")
                with self._jobs_lock:
                    self._jobs[job.id] = job
        else:
            # Fallback: ذخیره در database
            try:
                with get_db_session() as db:
                    db.execute(
                        text("""
                            INSERT INTO job_statuses (id, state, progress, message, result, error, created_at, updated_at)
                            VALUES (:id, :state, :progress, :message, :result, :error, to_timestamp(:created_at), to_timestamp(:updated_at))
                            ON CONFLICT (id) DO UPDATE SET
                                state = EXCLUDED.state,
                                progress = EXCLUDED.progress,
                                message = EXCLUDED.message,
                                result = EXCLUDED.result,
                                error = EXCLUDED.error,
                                updated_at = to_timestamp(:updated_at)
                        """),
                        {
                            "id": job.id,
                            "state": job.state,
                            "progress": job.progress,
                            "message": job.message,
                            "result": json.dumps(job.result) if job.result else None,
                            "error": job.error,
                            "created_at": job.created_at,
                            "updated_at": job.updated_at,
                        }
                    )
                    db.commit()
            except Exception as e:
                logger.warning(f"[JOB_MANAGER] Failed to save job {job.id} to database: {e}, using local memory")
                # Fallback به local memory
                with self._jobs_lock:
                    self._jobs[job.id] = job


