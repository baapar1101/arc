from __future__ import annotations

from typing import Dict, Any, Optional
from fastapi import APIRouter, Depends, Request, Body, Query
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.services.ai_plan_service import subscribe_to_plan
from adapters.db.repositories.ai_subscription_repository import AISubscriptionRepository
from adapters.db.repositories.ai_plan_repository import AIPlanRepository
from adapters.db.repositories.ai_usage_log_repository import AIUsageLogRepository
import json
from datetime import datetime

router = APIRouter(prefix="/ai/subscription", tags=["ai-subscription"])


def _build_subscription_response(subscription, request):
    import json
    plan = subscription.plan
    return success_response({
        "id": subscription.id,
        "user_id": subscription.user_id,
        "business_id": subscription.business_id,
        "plan_id": subscription.plan_id,
        "plan": {
            "id": plan.id,
            "code": plan.code,
            "name": plan.name,
            "plan_type": plan.plan_type,
            "pricing_config": json.loads(plan.pricing_config or "{}"),
            "usage_limits": json.loads(plan.usage_limits or "{}"),
            "features": json.loads(plan.features or "{}")
        },
        "subscription_type": subscription.subscription_type,
        "tokens_used": subscription.tokens_used,
        "tokens_limit": subscription.tokens_limit,
        "period_start": subscription.period_start.isoformat() if subscription.period_start else None,
        "period_end": subscription.period_end.isoformat() if subscription.period_end else None,
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
    repo = AISubscriptionRepository(db)
    subscription = repo.get_active_subscription(
        user_id=ctx.get_user_id(),
        business_id=business_id or ctx.business_id
    )
    
    if not subscription:
        return success_response(None, request, "اشتراک فعالی وجود ندارد")
    
    return _build_subscription_response(subscription, request)


@router.get("/current", summary="دریافت اشتراک فعلی (alias)")
async def get_subscription_current(
    request: Request,
    business_id: Optional[int] = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """Alias برای سازگاری با frontend"""
    repo = AISubscriptionRepository(db)
    subscription = repo.get_active_subscription(
        user_id=ctx.get_user_id(),
        business_id=business_id or ctx.business_id
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
    result = subscribe_to_plan(
        db=db,
        user_id=ctx.get_user_id(),
        business_id=business_id or ctx.business_id,
        plan_id=plan_id,
        period=period
    )
    
    subscription = result["subscription"]
    invoice = result.get("invoice")
    
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
            "status": invoice.status
        }
    
    return success_response(response_data, request, "اشتراک با موفقیت ایجاد شد")


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
    
    repo = AIUsageLogRepository(db)
    
    from_dt = datetime.fromisoformat(from_date) if from_date else None
    to_dt = datetime.fromisoformat(to_date) if to_date else None
    
    stats = repo.get_usage_statistics(
        user_id=ctx.get_user_id(),
        business_id=business_id or ctx.business_id,
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
    repo = AISubscriptionRepository(db)
    subscription = repo.get_active_subscription(
        user_id=ctx.get_user_id(),
        business_id=business_id or ctx.business_id
    )
    
    if not subscription:
        return success_response(None, request, "اشتراک فعالی برای لغو یافت نشد")
    
    subscription.is_active = False
    subscription.period_end = datetime.utcnow()
    subscription.updated_at = datetime.utcnow()
    db.commit()
    
    return success_response(
        {"id": subscription.id},
        request,
        "اشتراک با موفقیت لغو شد"
    )

