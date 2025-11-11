from __future__ import annotations

from fastapi import APIRouter, Request

from app.services.job_manager import JobManager
from app.core.responses import success_response, ApiError

router = APIRouter(prefix="/jobs", tags=["jobs"])


@router.get("/{job_id}")
async def get_job_status(request: Request, job_id: str):
    st = JobManager.instance().get(job_id)
    if not st:
        raise ApiError("JOB_NOT_FOUND", "Job not found", http_status=404)
    return success_response(st.to_dict(), request=request)


