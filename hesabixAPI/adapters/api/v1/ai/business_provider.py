from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, Path, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_permission_dep
from app.core.responses import ApiError, success_response
from app.services.ai.business_ai_provider_service import (
    business_has_active_byok_subscription,
    delete_config,
    get_config,
    serialize_config,
    test_connection,
    upsert_config,
)

router = APIRouter(
    prefix="/businesses/{business_id}/ai-provider",
    tags=["ارائه‌دهنده AI اختصاصی"],
    dependencies=[Depends(require_business_permission_dep("settings", "manage_ai_provider"))],
)


@router.get("", summary="دریافت تنظیمات ارائه‌دهنده اختصاصی")
async def get_business_ai_provider(
    request: Request,
    business_id: int = Path(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    has_byok, plan = business_has_active_byok_subscription(
        db,
        user_id=ctx.get_user_id(),
        business_id=business_id,
    )
    cfg = get_config(db, business_id)
    data = serialize_config(cfg, plan=plan if has_byok else None)
    data["has_byok_subscription"] = has_byok
    data["plan_code"] = plan.code if plan and has_byok else None
    data["plan_name"] = plan.name if plan and has_byok else None
    return success_response(data, request)


@router.put("", summary="ذخیره تنظیمات ارائه‌دهنده اختصاصی")
async def put_business_ai_provider(
    request: Request,
    business_id: int = Path(...),
    payload: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    cfg = upsert_config(
        db,
        business_id=business_id,
        user_id=ctx.get_user_id(),
        payload=payload or {},
    )
    _, plan = business_has_active_byok_subscription(
        db,
        user_id=ctx.get_user_id(),
        business_id=business_id,
    )
    data = serialize_config(cfg, plan=plan)
    data["has_byok_subscription"] = True
    return success_response(data, request, "تنظیمات ارائه‌دهنده ذخیره شد")


@router.post("/test", summary="تست اتصال ارائه‌دهنده اختصاصی")
async def test_business_ai_provider(
    request: Request,
    business_id: int = Path(...),
    model: Optional[str] = Body(None, embed=True),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    result = test_connection(
        db,
        business_id=business_id,
        user_id=ctx.get_user_id(),
        model=model,
    )
    return success_response(result, request, "اتصال برقرار شد")


@router.delete("", summary="حذف تنظیمات ارائه‌دهنده اختصاصی")
async def delete_business_ai_provider(
    request: Request,
    business_id: int = Path(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)
    delete_config(db, business_id)
    return success_response({"deleted": True}, request, "تنظیمات حذف شد")
