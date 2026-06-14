"""Admin API for AI skills marketplace moderation."""
from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import ApiError, success_response
from app.services.ai.ai_skill_service import (
    approve_package_publish,
    list_pending_packages,
    package_to_dict,
    reject_package_publish,
    seed_official_skills,
)

router = APIRouter(prefix="/admin/ai/skills", tags=["admin-ai-skills"])


def _require_superadmin(ctx: AuthContext) -> None:
    if not ctx.has_any_permission("system_settings", "superadmin"):
        raise ApiError("FORBIDDEN", "فقط مدیر سیستم", http_status=403)


@router.get("/pending", summary="مهارت‌های در انتظار تأیید")
async def list_pending(
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    skip: int = Query(0, ge=0),
    take: int = Query(50, ge=1, le=100),
) -> dict:
    _require_superadmin(ctx)
    rows, total = list_pending_packages(db, skip=skip, take=take)
    return success_response(
        data={
            "items": [package_to_dict(p, include_body=True) for p in rows],
            "total": total,
            "skip": skip,
            "take": take,
        },
        request=request,
        message="AI_SKILLS_PENDING_LISTED",
    )


@router.post("/packages/{package_id}/approve", summary="تأیید انتشار مهارت")
async def approve_package(
    request: Request,
    package_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    _require_superadmin(ctx)
    try:
        pkg = approve_package_publish(db, package_id)
    except ValueError:
        raise ApiError("SKILL_PACKAGE_NOT_FOUND", "بسته یافت نشد", http_status=404)
    return success_response(
        data=package_to_dict(pkg),
        request=request,
        message="AI_SKILL_APPROVED",
    )


@router.post("/packages/{package_id}/reject", summary="رد انتشار مهارت")
async def reject_package(
    request: Request,
    package_id: int,
    body: Dict[str, Any] = Body(default={}),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    _require_superadmin(ctx)
    reason = str(body.get("reason") or "")
    try:
        pkg = reject_package_publish(db, package_id, reason=reason)
    except ValueError:
        raise ApiError("SKILL_PACKAGE_NOT_FOUND", "بسته یافت نشد", http_status=404)
    return success_response(
        data=package_to_dict(pkg),
        request=request,
        message="AI_SKILL_REJECTED",
    )


@router.post("/seed-official", summary="درج مهارت‌های رسمی Hesabix")
async def seed_official(
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    _require_superadmin(ctx)
    count = seed_official_skills(db)
    return success_response(
        data={"created": count},
        request=request,
        message="AI_SKILLS_OFFICIAL_SEEDED",
    )
