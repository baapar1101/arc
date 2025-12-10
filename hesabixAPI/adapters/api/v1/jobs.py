from __future__ import annotations

from fastapi import APIRouter, Request, Depends, Body
from typing import Optional, Dict, Any

from app.services.job_manager import JobManager
from app.core.responses import success_response, ApiError
from app.core.queue import get_queue_service, QUEUE_DEFAULT, QUEUE_REPORTS
from app.core.auth_dependency import get_current_user, AuthContext
from app.services.jobs import generate_report_job

router = APIRouter(prefix="/jobs", tags=["jobs"])


@router.get("/{job_id}")
async def get_job_status(
    request: Request, 
    job_id: str, 
    ctx: AuthContext = Depends(get_current_user),
):
    """دریافت وضعیت job"""
    # این endpoint فقط از queue service استفاده می‌کند و نیازی به db ندارد
    queue_service = get_queue_service()
    
    # ابتدا از QueueService بررسی کن (برای RQ jobs)
    if queue_service and queue_service.enabled:
        job_status = queue_service.get_job_status(job_id)
        if job_status:
            # همیشه وضعیت job را برگردان (نه مستقیماً نتیجه)
            # Frontend خودش نتیجه را از job_status["result"] استخراج می‌کند
            return success_response(job_status, request=request)
    
    # Fallback به JobManager (برای memory-based jobs)
    st = JobManager.instance().get(job_id)
    if not st:
        raise ApiError("JOB_NOT_FOUND", "Job not found", http_status=404)
    return success_response(st.to_dict(), request=request)


@router.delete("/{job_id}")
async def cancel_job(request: Request, job_id: str, ctx: AuthContext = Depends(get_current_user)):
    """لغو یا حذف job"""
    queue_service = get_queue_service()
    
    if not queue_service.enabled:
        raise ApiError("QUEUE_DISABLED", "Queue service is disabled", http_status=503)
    
    # بررسی وجود job
    job_status = JobManager.instance().get(job_id)
    if not job_status:
        raise ApiError("JOB_NOT_FOUND", "Job not found", http_status=404)
    
    # لغو job
    cancelled = queue_service.cancel_job(job_id)
    if not cancelled:
        # اگر نتوانست لغو کند، سعی می‌کند حذف کند
        deleted = queue_service.delete_job(job_id)
        if not deleted:
            raise ApiError("JOB_CANCEL_FAILED", "Failed to cancel or delete job", http_status=500)
    
    return success_response({"job_id": job_id, "cancelled": True}, request=request)


@router.get("/queue/stats")
async def get_queue_stats(request: Request, ctx: AuthContext = Depends(get_current_user)):
    """دریافت آمار queues"""
    queue_service = get_queue_service()
    
    if not queue_service.enabled:
        return success_response({
            "enabled": False,
            "queues": {}
        }, request=request)
    
    from app.core.queue import (
        QUEUE_DEFAULT, QUEUE_HIGH_PRIORITY, QUEUE_LOW_PRIORITY,
        QUEUE_EMAIL, QUEUE_REPORTS, QUEUE_EXPORTS
    )
    
    queues = {
        "default": queue_service.get_queue_length(QUEUE_DEFAULT),
        "high": queue_service.get_queue_length(QUEUE_HIGH_PRIORITY),
        "low": queue_service.get_queue_length(QUEUE_LOW_PRIORITY),
        "email": queue_service.get_queue_length(QUEUE_EMAIL),
        "reports": queue_service.get_queue_length(QUEUE_REPORTS),
        "exports": queue_service.get_queue_length(QUEUE_EXPORTS),
    }
    
    return success_response({
        "enabled": True,
        "queues": queues
    }, request=request)


@router.get("/failed")
async def get_failed_jobs(
    request: Request,
    limit: int = 10,
    ctx: AuthContext = Depends(get_current_user)
):
    """دریافت لیست jobs ناموفق"""
    queue_service = get_queue_service()
    
    if not queue_service.enabled:
        return success_response({"jobs": []}, request=request)
    
    failed_jobs = queue_service.get_failed_jobs(limit=limit)
    return success_response({"jobs": failed_jobs}, request=request)


@router.post("/reports")
async def enqueue_report_job(
    request: Request,
    payload: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
):
    """
    ثبت یک job گزارش سنگین در صف Redis (QUEUE_REPORTS).
    
    Body:
      - report_type: نوع گزارش (مثلاً general_ledger, trial_balance, pnl و ...)
      - business_id: شناسه کسب‌وکار
      - params: پارامترهای گزارش (اختیاری)
    """
    queue_service = get_queue_service()
    if not queue_service or not queue_service.enabled:
        raise ApiError("QUEUE_DISABLED", "Queue service is disabled", http_status=503)
    
    report_type = str(payload.get("report_type") or "").strip()
    business_id = payload.get("business_id")
    params: Dict[str, Any] = payload.get("params") or {}
    
    if not report_type or not business_id:
        raise ApiError("VALIDATION_ERROR", "report_type و business_id الزامی هستند", http_status=400)
    
    user_id = ctx.get_user_id()
    
    job = queue_service.enqueue(
        generate_report_job,
        report_type,
        int(business_id),
        int(user_id),
        params=params,
        queue_name=QUEUE_REPORTS,
        timeout=1800,
        result_ttl=86400,
    )
    if not job:
        raise ApiError("JOB_ENQUEUE_FAILED", "ثبت job گزارش در صف ناموفق بود", http_status=500)
    
    return success_response(
        {
            "job_id": job.id,
            "queue": QUEUE_REPORTS,
            "report_type": report_type,
        },
        request=request,
        message="REPORT_JOB_ENQUEUED",
    )


