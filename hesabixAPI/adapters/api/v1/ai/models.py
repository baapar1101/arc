from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.db.repositories.ai_subscription_repository import AISubscriptionRepository
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import ApiError, success_response
from app.services.ai.ai_model_service import get_plan_default_model_code, list_models_for_user

router = APIRouter(prefix="/ai/models", tags=["هوش مصنوعی"])


@router.get("", summary="لیست مدل‌های مجاز برای کاربر")
async def list_available_models(
    request: Request,
    business_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    effective_business_id = business_id or ctx.business_id
    if effective_business_id and not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    plan = None
    preferred_model_code = None
    if effective_business_id:
        sub_repo = AISubscriptionRepository(db)
        subscription = sub_repo.get_active_subscription(
            user_id=ctx.get_user_id(),
            business_id=effective_business_id,
        )
        if subscription:
            plan = subscription.plan
            preferred_model_code = getattr(subscription, "preferred_model_code", None)

    models = list_models_for_user(db, plan, include_pricing=True)
    return success_response(
        {
            "models": models,
            "preferred_model_code": preferred_model_code,
            "plan_default_model": get_plan_default_model_code(plan),
        },
        request,
    )
