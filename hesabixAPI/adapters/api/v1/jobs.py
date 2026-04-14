from __future__ import annotations

from fastapi import APIRouter, Request, Depends, Body
from typing import Optional, Dict, Any

from app.services.job_manager import JobManager
from app.core.responses import success_response, ApiError
from app.core.queue import get_queue_service, QUEUE_DEFAULT, QUEUE_REPORTS
from app.core.auth_dependency import get_current_user, AuthContext
from app.services.jobs import generate_report_job

router = APIRouter(prefix="/jobs", tags=["jobs"])

def _ensure_job_access(ctx: AuthContext, job_meta: dict | None, job_id: str) -> None:
    """
    کنترل دسترسی به job:
    - فقط سازنده‌ی job (meta.user_id) یا superadmin مجاز است.
    """
    if ctx.is_superadmin():
        return
    meta = job_meta or {}
    meta_user_id = meta.get("user_id")
    try:
        if meta_user_id is None or int(meta_user_id) != int(ctx.get_user_id()):
            raise ApiError("FORBIDDEN", f"No access to job {job_id}", http_status=403)
    except ApiError:
        raise
    except Exception:
        raise ApiError("FORBIDDEN", f"No access to job {job_id}", http_status=403)


@router.get("/{job_id}")
async def get_job_status(
    request: Request, 
    job_id: str, 
    ctx: AuthContext = Depends(get_current_user),
):
    """دریافت وضعیت job"""
    import logging
    logger = logging.getLogger(__name__)
    
    logger.info(f"[GET_JOB_STATUS] Request for job_id: {job_id}, user_id: {ctx.get_user_id()}")
    
    queue_service = get_queue_service()
    logger.info(f"[GET_JOB_STATUS] Queue service enabled: {queue_service.enabled if queue_service else False}")
    
    # ابتدا از QueueService بررسی کن (برای RQ jobs)
    if queue_service and queue_service.enabled:
        logger.info(f"[GET_JOB_STATUS] Checking queue service for job {job_id}")
        queue_status = queue_service.get_job_status(job_id)
        if queue_status:
            logger.info(f"[GET_JOB_STATUS] Job {job_id} found in queue service, state: {queue_status.get('state')}")
            # بررسی مالکیت/دسترسی قبل از بازگرداندن status/result
            job_meta = queue_status.get("meta")
            _ensure_job_access(ctx, job_meta, job_id)
            
            # همیشه وضعیت job را برگردان (نه مستقیماً نتیجه)
            # Frontend خودش نتیجه را از job_status["result"] استخراج می‌کند
            return success_response(queue_status, request=request)
        else:
            logger.info(f"[GET_JOB_STATUS] Job {job_id} not found in queue service")
    else:
        logger.info(f"[GET_JOB_STATUS] Queue service not enabled or not available")
    
    # Fallback به JobManager (برای memory-based jobs مثل backup)
    logger.info(f"[GET_JOB_STATUS] Checking JobManager (memory-based) for job {job_id}")
    jm = JobManager.instance()
    job_status = jm.get(job_id)
    if job_status:
        logger.info(f"[GET_JOB_STATUS] Job {job_id} found in JobManager, state: {job_status.state}, message: {job_status.message}")
        # تبدیل JobStatus به فرمت مشابه QueueService
        from datetime import datetime
        try:
            created_at = None
            if job_status.created_at:
                try:
                    if isinstance(job_status.created_at, (int, float)):
                        created_at = datetime.fromtimestamp(job_status.created_at).isoformat()
                    elif isinstance(job_status.created_at, str):
                        created_at = job_status.created_at
                except (ValueError, OSError, TypeError) as e:
                    logger.warning(f"[GET_JOB_STATUS] Error parsing created_at for job {job_id}: {e}")
            
            updated_at = None
            if job_status.updated_at:
                try:
                    if isinstance(job_status.updated_at, (int, float)):
                        updated_at = datetime.fromtimestamp(job_status.updated_at).isoformat()
                    elif isinstance(job_status.updated_at, str):
                        updated_at = job_status.updated_at
                except (ValueError, OSError, TypeError) as e:
                    logger.warning(f"[GET_JOB_STATUS] Error parsing updated_at for job {job_id}: {e}")
            
            # Parse error message برای نمایش بهتر در frontend
            error_info = None
            if job_status.error:
                error_str = job_status.error
                # اگر error به صورت "CODE: message" است، parse کن
                if ":" in error_str:
                    parts = error_str.split(":", 1)
                    if len(parts) == 2:
                        error_code = parts[0].strip()
                        error_message = parts[1].strip()
                        error_info = {
                            "code": error_code,
                            "message": error_message,
                        }
                        # اگر details وجود دارد
                        if "| Details:" in error_message:
                            msg_parts = error_message.split("| Details:", 1)
                            error_info["message"] = msg_parts[0].strip()
                            try:
                                import json
                                # سعی کن details را parse کن
                                details_str = msg_parts[1].strip()
                                # اگر به صورت dict stringified است
                                if details_str.startswith("{") or details_str.startswith("["):
                                    error_info["details"] = json.loads(details_str)
                                else:
                                    error_info["details"] = details_str
                            except:
                                error_info["details"] = msg_parts[1].strip() if len(msg_parts) > 1 else None
                    else:
                        # اگر format خاصی ندارد، همان string را برگردان
                        error_info = error_str
                else:
                    # اگر format خاصی ندارد، همان string را برگردان
                    error_info = error_str
            
            status_dict = {
                "id": job_status.id,
                "state": job_status.state,
                "created_at": created_at,
                "updated_at": updated_at,
                "result": job_status.result,
                "error": error_info if error_info else job_status.error,
                "meta": {
                    "message": job_status.message,
                    "progress": job_status.progress,
                } if job_status.message else None,
            }
            # برای memory-based jobs، دسترسی را بررسی نمی‌کنیم (چون meta.user_id ندارند)
            # TODO: اضافه کردن کنترل دسترسی برای memory-based jobs
            return success_response(status_dict, request=request)
        except Exception as e:
            logger.error(f"[GET_JOB_STATUS] Error formatting job status for {job_id}: {e}", exc_info=True)
            raise ApiError("INTERNAL_ERROR", f"Error formatting job status: {str(e)}", http_status=500)
    else:
        logger.warning(f"[GET_JOB_STATUS] Job {job_id} not found in queue service or JobManager")
    
    raise ApiError("JOB_NOT_FOUND", "Job not found", http_status=404)


@router.delete("/{job_id}")
async def cancel_job(request: Request, job_id: str, ctx: AuthContext = Depends(get_current_user)):
    """لغو یا حذف job"""
    queue_service = get_queue_service()
    
    if not queue_service.enabled:
        raise ApiError("QUEUE_DISABLED", "Queue service is disabled", http_status=503)
    
    # بررسی وجود job + کنترل دسترسی
    job = queue_service.get_job(job_id)
    if job is None:
        raise ApiError("JOB_NOT_FOUND", "Job not found", http_status=404)
    _ensure_job_access(ctx, getattr(job, "meta", None), job_id)
    
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
    # اطلاعات عملیاتی → فقط superadmin
    if not ctx.is_superadmin():
        raise ApiError("FORBIDDEN", "Superadmin access required", http_status=403)
    queue_service = get_queue_service()
    
    if not queue_service.enabled:
        return success_response({
            "enabled": False,
            "queues": {}
        }, request=request)
    
    from app.core.queue import (
        QUEUE_DEFAULT, QUEUE_HIGH_PRIORITY, QUEUE_LOW_PRIORITY,
        QUEUE_EMAIL, QUEUE_REPORTS, QUEUE_EXPORTS, QUEUE_TAX
    )
    
    queues = {
        "default": queue_service.get_queue_length(QUEUE_DEFAULT),
        "high": queue_service.get_queue_length(QUEUE_HIGH_PRIORITY),
        "low": queue_service.get_queue_length(QUEUE_LOW_PRIORITY),
        "email": queue_service.get_queue_length(QUEUE_EMAIL),
        "reports": queue_service.get_queue_length(QUEUE_REPORTS),
        "exports": queue_service.get_queue_length(QUEUE_EXPORTS),
        "tax": queue_service.get_queue_length(QUEUE_TAX),
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
    # رجیستری failed می‌تواند شامل اطلاعات حساس باشد → فقط superadmin
    if not ctx.is_superadmin():
        raise ApiError("FORBIDDEN", "Superadmin access required", http_status=403)
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

    # business_id از body قابل جعل است → حتماً دسترسی را چک کن
    try:
        business_id_int = int(business_id)
    except Exception:
        raise ApiError("VALIDATION_ERROR", "business_id نامعتبر است", http_status=400)
    if not ctx.can_access_business(business_id_int):
        raise ApiError("FORBIDDEN", f"No access to business {business_id_int}", http_status=403)
    
    user_id = ctx.get_user_id()
    
    job = queue_service.enqueue(
        generate_report_job,
        report_type,
        business_id_int,
        int(user_id),
        params=params,
        queue_name=QUEUE_REPORTS,
        timeout=1800,
        result_ttl=86400,
    )
    if not job:
        raise ApiError("JOB_ENQUEUE_FAILED", "ثبت job گزارش در صف ناموفق بود", http_status=500)

    # متادیتای مالکیت برای enforce کردن دسترسی در /jobs/{job_id}
    try:
        job.meta = dict(job.meta or {})
        job.meta.update({
            "user_id": int(user_id),
            "business_id": int(business_id_int),
            "report_type": report_type,
        })
        job.save_meta()
    except Exception:
        # اگر save_meta مشکل داشت، لااقل job ساخته شده ولی ممکن است دسترسی بعدی سخت‌تر شود.
        # فعلاً fail نمی‌کنیم تا صف نخوابد.
        pass
    
    return success_response(
        {
            "job_id": job.id,
            "queue": QUEUE_REPORTS,
            "report_type": report_type,
        },
        request=request,
        message="REPORT_JOB_ENQUEUED",
    )


