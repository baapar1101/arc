from __future__ import annotations

from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Body, Depends, Path, Query, Request
from pydantic import BaseModel
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import ApiError, success_response
from adapters.db.models.ai_eval_case import AIEvalCase
from app.services.ai import ai_eval_service as eval_svc

router = APIRouter(prefix="/admin/ai/eval", tags=["admin-ai-eval"])


class EvalCaseBody(BaseModel):
    name: str
    description: Optional[str] = None
    role: str = "user"
    business_id: Optional[int] = None
    user_message: str
    expected_substrings: List[str] = []
    forbidden_substrings: List[str] = []
    use_tools: bool = False
    is_active: bool = True


class RunEvalBody(BaseModel):
    business_id: Optional[int] = None
    case_ids: Optional[List[int]] = None


class EvalScheduleBody(BaseModel):
    enabled: Optional[bool] = None
    cron_expression: Optional[str] = None
    timezone: Optional[str] = None
    business_id: Optional[int] = None
    min_pass_rate: Optional[int] = None


def _require_admin(ctx: AuthContext) -> None:
    if not ctx.has_any_permission("system_settings", "superadmin"):
        raise ApiError("FORBIDDEN", "فقط مدیر سیستم", http_status=403)


@router.get("/cases", summary="لیست سناریوهای ارزیابی")
async def list_eval_cases(
    request: Request,
    active_only: bool = Query(True),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    rows = eval_svc.list_cases(db, active_only=active_only)
    return success_response([eval_svc.case_to_dict(r) for r in rows], request)


@router.post("/cases", summary="ایجاد سناریو")
async def create_eval_case(
    request: Request,
    body: EvalCaseBody = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    row = eval_svc.create_case(db, body.model_dump())
    return success_response(eval_svc.case_to_dict(row), request, "سناریو ایجاد شد")


@router.put("/cases/{case_id}", summary="ویرایش سناریو")
async def update_eval_case(
    case_id: int = Path(...),
    request: Request = None,
    body: EvalCaseBody = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    row = eval_svc.update_case(db, case_id, body.model_dump())
    if not row:
        raise ApiError("NOT_FOUND", "سناریو یافت نشد", http_status=404)
    return success_response(eval_svc.case_to_dict(row), request)


@router.delete("/cases/{case_id}", summary="حذف سناریو")
async def delete_eval_case(
    case_id: int = Path(...),
    request: Request = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    if not eval_svc.delete_case(db, case_id):
        raise ApiError("NOT_FOUND", "سناریو یافت نشد", http_status=404)
    return success_response({"id": case_id}, request, "حذف شد")


@router.get("/runs", summary="اجراهای اخیر")
async def list_eval_runs(
    request: Request,
    limit: int = Query(30, ge=1, le=100),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    return success_response(eval_svc.list_runs(db, limit=limit), request)


@router.get("/runs/{run_id}", summary="جزئیات اجرا")
async def get_eval_run(
    run_id: int = Path(...),
    request: Request = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    data = eval_svc.get_run_with_results(db, run_id)
    if not data:
        raise ApiError("NOT_FOUND", "اجرا یافت نشد", http_status=404)
    return success_response(data, request)


@router.post("/runs", summary="اجرای ارزیابی")
async def run_eval(
    request: Request,
    body: RunEvalBody = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    try:
        result = await eval_svc.run_eval_suite(
            db,
            ctx,
            business_id=body.business_id,
            case_ids=body.case_ids,
        )
    except ValueError as exc:
        raise ApiError("NO_CASES", str(exc), http_status=400) from exc
    return success_response(result, request, "ارزیابی انجام شد")


@router.post("/cases/seed-defaults", summary="ایجاد سناریوهای پیش‌فرض")
async def seed_default_eval_cases(
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    defaults = [
        {
            "name": "تحلیل فروش — ساختار پاسخ",
            "user_message": "خلاصه وضعیت فروش هفتگی را بده.",
            "expected_substrings": ["فروش", "خلاصه"],
            "forbidden_substrings": ["نمی‌دانم"],
            "use_tools": False,
        },
        {
            "name": "راهنمای فاکتور",
            "user_message": "چطور فاکتور فروش ثبت کنم؟",
            "expected_substrings": ["فاکتور"],
            "forbidden_substrings": [],
            "use_tools": False,
        },
        {
            "name": "نمودار — بلوک chart",
            "user_message": "روند فروش ۴ هفته را با نمودار نشان بده.",
            "expected_substrings": ["chart"],
            "forbidden_substrings": [],
            "use_tools": False,
        },
    ]
    created = 0
    for item in defaults:
        existing = db.query(AIEvalCase).filter(AIEvalCase.name == item["name"]).first()
        if existing:
            continue
        eval_svc.create_case(db, item)
        created += 1
    return success_response({"created": created}, request, "سناریوهای پیش‌فرض آماده شد")


@router.get("/schedule", summary="تنظیمات زمان‌بندی ارزیابی")
async def get_eval_schedule(
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    from app.services.ai.ai_eval_schedule_service import get_schedule, schedule_to_dict

    return success_response(schedule_to_dict(get_schedule(db)), request)


@router.put("/schedule", summary="به‌روزرسانی زمان‌بندی ارزیابی")
async def update_eval_schedule(
    request: Request,
    body: EvalScheduleBody = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    from app.services.ai.ai_eval_schedule_service import schedule_to_dict, update_schedule

    row = update_schedule(db, body.model_dump(exclude_unset=True))
    return success_response(schedule_to_dict(row), request, "زمان‌بندی ذخیره شد")


@router.post("/schedule/run-now", summary="اجرای فوری ارزیابی زمان‌بندی‌شده")
async def run_eval_schedule_now(
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    from app.services.ai.ai_eval_schedule_service import run_eval_suite
    from app.services.ai.ai_eval_schedule_service import get_schedule

    sched = get_schedule(db)
    try:
        result = await run_eval_suite(db, ctx, business_id=sched.business_id)
    except ValueError as exc:
        raise ApiError("NO_CASES", str(exc), http_status=400) from exc
    return success_response(result, request, "ارزیابی اجرا شد")


@router.get("/feedback/analytics", summary="تحلیل بازخورد سراسری")
async def admin_feedback_analytics(
    request: Request,
    days: int = Query(30, ge=1, le=365),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    from app.services.ai.ai_feedback_analytics_service import get_feedback_analytics

    data = get_feedback_analytics(db, days=days)
    return success_response(data, request)
