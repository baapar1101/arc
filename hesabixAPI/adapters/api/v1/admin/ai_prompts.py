from __future__ import annotations

from typing import Dict, Any, List
from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.services.ai.prompt_service import update_default_prompt
from adapters.db.repositories.ai_prompt_repository import AIPromptRepository
from adapters.db.models.ai_prompt import PromptRole, PromptType

router = APIRouter(prefix="/admin/ai/prompts", tags=["admin-ai-prompts"])


@router.get("/default", summary="دریافت prompt های پیش‌فرض")
async def get_default_prompts(
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """دریافت prompt های پیش‌فرض (فقط مدیر سیستم)"""
    if not ctx.has_any_permission("system_settings", "superadmin"):
        raise ApiError("FORBIDDEN", "فقط مدیر سیستم می‌تواند prompt های پیش‌فرض را مشاهده کند", http_status=403)
    
    repo = AIPromptRepository(db)
    prompts = repo.get_all_default_prompts()
    
    result = []
    for prompt in prompts:
        result.append({
            "id": prompt.id,
            "role": prompt.role,
            "prompt_type": prompt.prompt_type,
            "title": prompt.title,
            "content": prompt.content,
            "is_default": prompt.is_default,
            "is_active": prompt.is_active,
            "created_at": prompt.created_at.isoformat() if prompt.created_at else None,
            "updated_at": prompt.updated_at.isoformat() if prompt.updated_at else None
        })
    
    return success_response(result, request)


@router.put("/default/{role}", summary="به‌روزرسانی prompt پیش‌فرض")
async def update_default_prompt_endpoint(
    role: str,
    request: Request,
    content: str = Body(..., embed=True),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """به‌روزرسانی prompt پیش‌فرض (فقط مدیر سیستم)"""
    if not ctx.has_any_permission("system_settings", "superadmin"):
        raise ApiError("FORBIDDEN", "فقط مدیر سیستم می‌تواند prompt پیش‌فرض را ویرایش کند", http_status=403)
    
    try:
        prompt_role = PromptRole(role)
    except ValueError:
        raise ApiError("INVALID_ROLE", f"نقش نامعتبر: {role}", http_status=400)
    
    prompt = update_default_prompt(db, prompt_role, content)
    
    return success_response({
        "id": prompt.id,
        "role": prompt.role,
        "prompt_type": prompt.prompt_type,
        "title": prompt.title,
        "content": prompt.content
    }, request, "Prompt پیش‌فرض با موفقیت به‌روزرسانی شد")

