from __future__ import annotations

from typing import Dict, Any, Optional
from fastapi import APIRouter, Depends, Request, Body, Query
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.services.ai_plan_service import subscribe_to_plan
from app.services.ai.ai_model_service import (
    list_models_for_user,
    serialize_plan_for_user,
    validate_model_selection,
)
from adapters.db.repositories.ai_subscription_repository import AISubscriptionRepository
from adapters.db.repositories.ai_plan_repository import AIPlanRepository
from adapters.db.repositories.ai_usage_log_repository import AIUsageLogRepository
import json
from datetime import datetime

router = APIRouter(prefix="/ai/subscription", tags=["هوش مصنوعی"])


def _build_subscription_response(subscription, request):
    import json
    from app.services.ai.ai_model_service import serialize_plan_for_user
    from app.services.ai.ai_quota_helpers import effective_tokens_limit

    plan = subscription.plan
    return success_response({
        "id": subscription.id,
        "user_id": subscription.user_id,
        "business_id": subscription.business_id,
        "plan_id": subscription.plan_id,
        "preferred_model_code": getattr(subscription, "preferred_model_code", None),
        "plan": serialize_plan_for_user(plan) if plan else None,
        "subscription_type": subscription.subscription_type,
        "tokens_used": subscription.tokens_used,
        "tokens_limit": effective_tokens_limit(subscription.tokens_limit),
        "period_start": subscription.period_start.isoformat() if subscription.period_start else None,
        "period_end": subscription.period_end.isoformat() if subscription.period_end else None,
        "expires_at": (
            subscription.expires_at.isoformat()
            if getattr(subscription, "expires_at", None)
            else (
                subscription.period_end.isoformat()
                if subscription.period_end
                else None
            )
        ),
        "is_active": subscription.is_active,
        "auto_renew": getattr(subscription, "auto_renew", False),
        "created_at": subscription.created_at.isoformat() if getattr(subscription, "created_at", None) else None,
        "updated_at": subscription.updated_at.isoformat() if getattr(subscription, "updated_at", None) else None,
    }, request)


@router.get("", summary="دریافت اشتراک فعلی")
async def get_subscription(
    request: Request,
    business_id: Optional[int] = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """دریافت اشتراک فعال کاربر"""
    effective_business_id = business_id or ctx.business_id
    if effective_business_id and (not ctx.can_access_business(int(effective_business_id))):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)
    repo = AISubscriptionRepository(db)
    subscription = repo.get_active_subscription(
        user_id=ctx.get_user_id(),
        business_id=effective_business_id
    )
    
    if not subscription:
        return success_response(None, request, "اشتراک فعالی وجود ندارد")
    
    return _build_subscription_response(subscription, request)


@router.get("/plans", summary="لیست پلن‌های فعال (عمومی)")
async def list_public_plans(
    request: Request,
    business_id: Optional[int] = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """دریافت پلن‌های فعال برای انتخاب توسط کاربر (بدون نیاز به دسترسی ادمین)."""
    effective_business_id = business_id or ctx.business_id
    if effective_business_id and not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    plan_repo = AIPlanRepository(db)
    plans = plan_repo.get_active_plans()
    serialized = [serialize_plan_for_user(p) for p in plans]

    current_plan_id = None
    if effective_business_id:
        sub_repo = AISubscriptionRepository(db)
        subscription = sub_repo.get_active_subscription(
            user_id=ctx.get_user_id(),
            business_id=effective_business_id,
        )
        if subscription:
            current_plan_id = subscription.plan_id

    return success_response(
        {
            "plans": serialized,
            "current_plan_id": current_plan_id,
        },
        request,
    )


@router.put("/preferred-model", summary="تنظیم مدل ترجیحی")
async def set_preferred_model(
    request: Request,
    model_code: str = Body(..., embed=True),
    business_id: Optional[int] = Body(None, embed=True),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    effective_business_id = business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    sub_repo = AISubscriptionRepository(db)
    subscription = sub_repo.get_active_subscription(
        user_id=ctx.get_user_id(),
        business_id=effective_business_id,
    )
    if not subscription:
        raise ApiError("NO_ACTIVE_SUBSCRIPTION", "اشتراک فعالی وجود ندارد", http_status=400)

    plan = subscription.plan
    validate_model_selection(db, plan, model_code.strip())

    subscription.preferred_model_code = model_code.strip()
    db.commit()
    db.refresh(subscription)

    return success_response(
        {
            "preferred_model_code": subscription.preferred_model_code,
            "available_models": list_models_for_user(db, plan, include_pricing=True),
        },
        request,
        "مدل ترجیحی ذخیره شد",
    )


@router.get("/current", summary="دریافت اشتراک فعلی (alias)")
async def get_subscription_current(
    request: Request,
    business_id: Optional[int] = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """Alias برای سازگاری با frontend"""
    effective_business_id = business_id or ctx.business_id
    if effective_business_id and (not ctx.can_access_business(int(effective_business_id))):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)
    repo = AISubscriptionRepository(db)
    subscription = repo.get_active_subscription(
        user_id=ctx.get_user_id(),
        business_id=effective_business_id
    )
    
    if not subscription:
        return success_response(None, request, "اشتراک فعالی وجود ندارد")
    
    return _build_subscription_response(subscription, request)


@router.post("/subscribe", summary="اشتراک به پلن")
async def subscribe_to_plan_endpoint(
    request: Request,
    plan_id: int = Body(..., embed=True),
    business_id: Optional[int] = Body(None, embed=True),
    period: str = Body("monthly", embed=True),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """اشتراک به یک پلن AI"""
    effective_business_id = business_id or ctx.business_id
    if not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)
    result = subscribe_to_plan(
        db=db,
        user_id=ctx.get_user_id(),
        business_id=effective_business_id,
        plan_id=plan_id,
        period=period
    )
    
    subscription = result["subscription"]
    invoice = result.get("invoice")
    payment = result.get("payment")
    
    response_data = {
        "subscription": {
            "id": subscription.id,
            "plan_id": subscription.plan_id,
            "user_id": subscription.user_id,
            "business_id": subscription.business_id,
            "subscription_type": subscription.subscription_type,
            "tokens_used": subscription.tokens_used,
            "tokens_limit": subscription.tokens_limit,
            "period_start": subscription.period_start.isoformat() if subscription.period_start else None,
            "period_end": subscription.period_end.isoformat() if subscription.period_end else None,
            "is_active": subscription.is_active,
            "created_at": subscription.created_at.isoformat() if subscription.created_at else None,
            "updated_at": subscription.updated_at.isoformat() if subscription.updated_at else None,
        }
    }
    
    if invoice:
        response_data["invoice"] = {
            "id": invoice.id,
            "code": invoice.code,
            "total": float(invoice.total),
            "status": invoice.status,
            "document_id": invoice.document_id,
            "wallet_transaction_id": invoice.wallet_transaction_id,
        }
    
    if payment:
        response_data["payment"] = payment

    return success_response(response_data, request, "اشتراک با موفقیت ایجاد شد")


@router.post("/upgrade", summary="ارتقا به پلن دیگر")
async def upgrade_to_plan(
    request: Request,
    plan_id: int = Body(..., embed=True),
    business_id: Optional[int] = Body(None, embed=True),
    period: str = Body("monthly", embed=True),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """ارتقا به پلن دیگر؛ منطق با subscribe یکسان است (اشتراک فعال قبلی غیرفعال می‌شود)."""
    return await subscribe_to_plan_endpoint(
        request=request,
        plan_id=plan_id,
        business_id=business_id,
        period=period,
        db=db,
        ctx=ctx,
    )


@router.get("/usage", summary="آمار استفاده")
async def get_usage_statistics(
    request: Request,
    business_id: Optional[int] = None,
    from_date: Optional[str] = None,
    to_date: Optional[str] = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """دریافت آمار استفاده از AI"""
    from datetime import datetime
    
    effective_business_id = business_id or ctx.business_id
    if effective_business_id and (not ctx.can_access_business(int(effective_business_id))):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    repo = AIUsageLogRepository(db)
    
    from_dt = datetime.fromisoformat(from_date) if from_date else None
    to_dt = datetime.fromisoformat(to_date) if to_date else None
    
    stats = repo.get_usage_statistics(
        user_id=ctx.get_user_id(),
        business_id=effective_business_id,
        from_date=from_dt,
        to_date=to_dt
    )
    
    return success_response(stats, request)


@router.post("/cancel", summary="لغو اشتراک فعال")
async def cancel_subscription(
    request: Request,
    business_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """لغو اشتراک فعال کاربر"""
    effective_business_id = business_id or ctx.business_id
    if effective_business_id and (not ctx.can_access_business(int(effective_business_id))):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    repo = AISubscriptionRepository(db)
    subscription = repo.get_active_subscription(
        user_id=ctx.get_user_id(),
        business_id=effective_business_id
    )
    
    if not subscription:
        return success_response(None, request, "اشتراک فعالی برای لغو یافت نشد")
    
    subscription.is_active = False
    subscription.period_end = datetime.utcnow()
    subscription.expires_at = datetime.utcnow()
    subscription.updated_at = datetime.utcnow()
    db.commit()
    
    return success_response(
        {"id": subscription.id},
        request,
        "اشتراک با موفقیت لغو شد"
    )

