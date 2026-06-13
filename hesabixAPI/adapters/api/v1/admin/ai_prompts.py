from __future__ import annotations

from typing import Dict, Any, Optional

from fastapi import APIRouter, Depends, Request, Body, Path, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.services.ai.prompt_service import (
    list_effective_default_prompts,
    update_default_prompt_by_key,
    delete_default_prompt_by_key,
    reset_default_prompt_by_key,
)

router = APIRouter(prefix="/admin/ai/prompts", tags=["admin-ai-prompts"])


class UpdatePromptRequest(BaseModel):
    content: str = Field(..., min_length=1)


@router.get("/default", summary="دریافت prompt های پیش‌فرض")
async def get_default_prompts(
    request: Request,
    role: Optional[str] = Query(None),
    category: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    if not ctx.has_any_permission("system_settings", "superadmin"):
        raise ApiError(
            "FORBIDDEN",
            "فقط مدیر سیستم می‌تواند prompt های پیش‌فرض را مشاهده کند",
            http_status=403,
        )

    prompts = list_effective_default_prompts(db, role=role, category=category)
    return success_response(prompts, request)


@router.get("/default/{prompt_key}", summary="دریافت یک prompt پیش‌فرض")
async def get_default_prompt(
    prompt_key: str = Path(...),
    request: Request = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    if not ctx.has_any_permission("system_settings", "superadmin"):
        raise ApiError("FORBIDDEN", "دسترسی مجاز نیست", http_status=403)

    prompts = list_effective_default_prompts(db)
    match = next((p for p in prompts if p["prompt_key"] == prompt_key), None)
    if not match:
        raise ApiError("PROMPT_NOT_FOUND", f"Prompt یافت نشد: {prompt_key}", http_status=404)
    return success_response(match, request)


@router.put("/default/{prompt_key}", summary="به‌روزرسانی prompt پیش‌فرض")
async def update_default_prompt_endpoint(
    prompt_key: str = Path(...),
    request: Request = None,
    body: UpdatePromptRequest = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    if not ctx.has_any_permission("system_settings", "superadmin"):
        raise ApiError("FORBIDDEN", "فقط مدیر سیستم می‌تواند prompt پیش‌فرض را ویرایش کند", http_status=403)

    try:
        prompt = update_default_prompt_by_key(db, prompt_key, body.content.strip())
    except ValueError as exc:
        raise ApiError("INVALID_PROMPT_KEY", str(exc), http_status=400)

    return success_response(
        {
            "id": prompt.id,
            "prompt_key": prompt.prompt_key,
            "role": prompt.role,
            "prompt_type": prompt.prompt_type,
            "category": prompt.category,
            "title": prompt.title,
            "content": prompt.content,
            "source": "database",
        },
        request,
        "Prompt پیش‌فرض با موفقیت به‌روزرسانی شد",
    )


@router.post("/default/{prompt_key}/reset", summary="بازگشت prompt به مقدار پیش‌فرض کد")
async def reset_default_prompt_endpoint(
    prompt_key: str = Path(...),
    request: Request = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    if not ctx.has_any_permission("system_settings", "superadmin"):
        raise ApiError("FORBIDDEN", "دسترسی مجاز نیست", http_status=403)

    try:
        data = reset_default_prompt_by_key(db, prompt_key)
    except ValueError as exc:
        raise ApiError("INVALID_PROMPT_KEY", str(exc), http_status=400)

    return success_response(data, request, "Prompt به مقدار پیش‌فرض بازگردانده شد")


@router.delete("/default/{prompt_key}", summary="حذف prompt سفارشی (بازگشت به fallback)")
async def delete_default_prompt_endpoint(
    prompt_key: str = Path(...),
    request: Request = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    if not ctx.has_any_permission("system_settings", "superadmin"):
        raise ApiError("FORBIDDEN", "دسترسی مجاز نیست", http_status=403)

    delete_default_prompt_by_key(db, prompt_key)
    data = reset_default_prompt_by_key(db, prompt_key)
    return success_response(data, request, "Prompt سفارشی حذف شد")
