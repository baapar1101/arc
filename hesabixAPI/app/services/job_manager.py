from __future__ import annotations

import threading
import time
import uuid
from dataclasses import dataclass, field
from typing import Any, Dict, Optional

from app.core.queue import get_queue_service, QueueService


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
        self._jobs: Dict[str, JobStatus] = {}
        self._jobs_lock = threading.Lock()
        self._queue_service: Optional[QueueService] = None

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
        job_id = str(uuid.uuid4())
        status = JobStatus(id=job_id, message=message or "Queued")
        with self._jobs_lock:
            self._jobs[job_id] = status
        return job_id

    def get(self, job_id: str) -> Optional[JobStatus]:
        """دریافت وضعیت job"""
        # ابتدا از queue service بررسی می‌کنیم
        if self.queue_service.enabled:
            queue_status = self.queue_service.get_job_status(job_id)
            if queue_status:
                # تبدیل به JobStatus
                state_map = {
                    "queued": "queued",
                    "started": "running",
                    "finished": "succeeded",
                    "failed": "failed",
                    "deferred": "queued",
                    "scheduled": "queued",
                }
                status = JobStatus(
                    id=queue_status["id"],
                    state=state_map.get(queue_status["state"], "queued"),
                    message=queue_status.get("meta", {}).get("message"),
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
        
        # Fallback به memory-based jobs
        with self._jobs_lock:
            return self._jobs.get(job_id)

    def start(self, job_id: str, message: str | None = None) -> None:
        st = self.get(job_id)
        if not st:
            return
        st.state = "running"
        st.message = message or "Running"
        st.updated_at = time.time()

    def update(self, job_id: str, progress: int, message: str | None = None) -> None:
        st = self.get(job_id)
        if not st:
            return
        st.progress = max(0, min(100, progress))
        if message is not None:
            st.message = message
        st.updated_at = time.time()

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

    def fail(self, job_id: str, error: str, message: str | None = None) -> None:
        st = self.get(job_id)
        if not st:
            return
        st.state = "failed"
        st.error = error
        if message is not None:
            st.message = message
        st.updated_at = time.time()


