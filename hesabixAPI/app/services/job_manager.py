from __future__ import annotations

import threading
import time
import uuid
from dataclasses import dataclass, field
from typing import Any, Dict, Optional


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

    @classmethod
    def instance(cls) -> "JobManager":
        with cls._lock:
            if cls._instance is None:
                cls._instance = JobManager()
            return cls._instance

    def create(self, message: str | None = None) -> str:
        job_id = str(uuid.uuid4())
        status = JobStatus(id=job_id, message=message or "Queued")
        with self._jobs_lock:
            self._jobs[job_id] = status
        return job_id

    def get(self, job_id: str) -> Optional[JobStatus]:
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


