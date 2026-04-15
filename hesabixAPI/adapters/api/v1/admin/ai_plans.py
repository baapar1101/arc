from __future__ import annotations

import json
from typing import Dict, Any, Optional

from fastapi import APIRouter, Depends, Request, Body, Query
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.services.ai_plan_service import create_plan, update_plan
from adapters.db.repositories.ai_plan_repository import AIPlanRepository
from adapters.db.models.ai_plan import AIPlan

router = APIRouter(prefix="/admin/ai/plans", tags=["admin-ai-plans"])


def _serialize_plan(plan: AIPlan) -> Dict[str, Any]:
    return {
        "id": plan.id,
        "code": plan.code,
        "name": plan.name,
        "description": plan.description,
        "plan_type": plan.plan_type,
        "pricing_config": json.loads(plan.pricing_config or "{}"),
        "usage_limits": json.loads(plan.usage_limits or "{}"),
        "features": json.loads(plan.features or "{}"),
        "tokens_limit": plan.tokens_limit,
        "monthly_tokens_limit": plan.monthly_tokens_limit,
        "is_active": plan.is_active,
        "auto_renew": plan.auto_renew,
        "created_at": plan.created_at.isoformat() if plan.created_at else None,
        "updated_at": plan.updated_at.isoformat() if plan.updated_at else None,
    }


@router.post("", summary="ایجاد پلن AI جدید")
async def create_ai_plan(
    request: Request,
    payload: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """ایجاد پلن AI جدید (فقط مدیر سیستم)"""
    if not ctx.has_any_permission("system_settings", "superadmin"):
        raise ApiError("FORBIDDEN", "فقط مدیر سیستم می‌تواند پلن ایجاد کند", http_status=403)

    plan = create_plan(
        db=db,
        code=payload["code"],
        name=payload["name"],
        plan_type=payload["plan_type"],
        pricing_config=payload.get("pricing_config") or {},
        usage_limits=payload.get("usage_limits") or {},
        features=payload.get("features") or {},
        description=payload.get("description"),
        tokens_limit=payload.get("tokens_limit"),
        monthly_tokens_limit=payload.get("monthly_tokens_limit"),
        auto_renew=bool(payload.get("auto_renew", False)),
        is_active=bool(payload.get("is_active", True)),
    )

    return success_response(_serialize_plan(plan), request, "پلن با موفقیت ایجاد شد")


@router.get("", summary="لیست پلن‌های AI")
async def list_ai_plans(
    request: Request,
    only_active: Optional[bool] = Query(None),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """دریافت لیست پلن‌های AI (فقط مدیر سیستم)"""
    if not ctx.has_any_permission("system_settings", "superadmin"):
        raise ApiError("FORBIDDEN", "فقط مدیر سیستم می‌تواند پلن‌ها را مشاهده کند", http_status=403)

    repo = AIPlanRepository(db)
    if only_active:
        plans = repo.get_active_plans()
    else:
        plans = repo.get_all()

    result = [_serialize_plan(p) for p in plans]
    return success_response(result, request)


@router.get("/{plan_id}", summary="جزئیات پلن")
async def get_ai_plan(
    plan_id: int,
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """دریافت جزئیات یک پلن (فقط مدیر سیستم)"""
    if not ctx.has_any_permission("system_settings", "superadmin"):
        raise ApiError("FORBIDDEN", "فقط مدیر سیستم می‌تواند پلن را مشاهده کند", http_status=403)

    repo = AIPlanRepository(db)
    plan = repo.get_by_id(plan_id)

    if not plan:
        raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد", http_status=404)

    return success_response(_serialize_plan(plan), request)


@router.put("/{plan_id}", summary="ویرایش پلن")
async def update_ai_plan(
    plan_id: int,
    request: Request,
    payload: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """ویرایش پلن (فقط مدیر سیستم)"""
    if not ctx.has_any_permission("system_settings", "superadmin"):
        raise ApiError("FORBIDDEN", "فقط مدیر سیستم می‌تواند پلن را ویرایش کند", http_status=403)

    allowed_keys = (
        "name",
        "description",
        "pricing_config",
        "usage_limits",
        "features",
        "is_active",
        "plan_type",
        "tokens_limit",
        "monthly_tokens_limit",
        "auto_renew",
    )
    updates = {k: payload[k] for k in allowed_keys if k in payload}
    plan = update_plan(db, plan_id, **updates)

    return success_response(_serialize_plan(plan), request, "پلن با موفقیت به‌روزرسانی شد")


@router.delete("/{plan_id}", summary="حذف/غیرفعال کردن پلن")
async def delete_ai_plan(
    plan_id: int,
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """غیرفعال کردن پلن (فقط مدیر سیستم)"""
    if not ctx.has_any_permission("system_settings", "superadmin"):
        raise ApiError("FORBIDDEN", "فقط مدیر سیستم می‌تواند پلن را حذف کند", http_status=403)

    repo = AIPlanRepository(db)
    plan = repo.get_by_id(plan_id)

    if not plan:
        raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد", http_status=404)

    plan.is_active = False
    db.commit()

    return success_response({"id": plan.id}, request, "پلن با موفقیت غیرفعال شد")
