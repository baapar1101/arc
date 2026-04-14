from __future__ import annotations

from typing import Dict, Any, List
from fastapi import APIRouter, Depends, Request, Body, Path
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.services.ai.prompt_service import create_user_prompt
from adapters.db.repositories.ai_prompt_repository import AIPromptRepository
from adapters.db.models.ai_prompt import PromptRole, PromptType
from pydantic import BaseModel

router = APIRouter(prefix="/ai/prompts", tags=["هوش مصنوعی"])


class CreatePromptRequest(BaseModel):
    role: str
    title: str
    content: str
    prompt_type: str = "system"


@router.get("/my", summary="دریافت prompt های شخصی")
async def get_my_prompts(
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """دریافت prompt های شخصی کاربر"""
    repo = AIPromptRepository(db)
    prompts = repo.get_user_prompts(ctx.get_user_id())
    
    result = []
    for prompt in prompts:
        result.append({
            "id": prompt.id,
            "role": prompt.role,
            "prompt_type": prompt.prompt_type,
            "title": prompt.title,
            "content": prompt.content,
            "is_active": prompt.is_active,
            "created_at": prompt.created_at.isoformat() if prompt.created_at else None,
            "updated_at": prompt.updated_at.isoformat() if prompt.updated_at else None
        })
    
    return success_response(result, request)


@router.post("/my", summary="ایجاد prompt شخصی")
async def create_my_prompt(
    request: Request,
    prompt_data: CreatePromptRequest = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """ایجاد prompt شخصی"""
    try:
        role = PromptRole(prompt_data.role)
        prompt_type = PromptType(prompt_data.prompt_type)
    except ValueError as e:
        raise ApiError("INVALID_ROLE_OR_TYPE", f"نقش یا نوع نامعتبر: {e}", http_status=400)
    
    prompt = create_user_prompt(
        db=db,
        user_id=ctx.get_user_id(),
        role=role,
        title=prompt_data.title,
        content=prompt_data.content,
        prompt_type=prompt_type
    )
    
    return success_response({
        "id": prompt.id,
        "role": prompt.role,
        "prompt_type": prompt.prompt_type,
        "title": prompt.title,
        "content": prompt.content
    }, request, "Prompt شخصی با موفقیت ایجاد شد")


@router.put("/my/{prompt_id}", summary="ویرایش prompt شخصی")
async def update_my_prompt(
    prompt_id: int = Path(...),
    request: Request = None,
    title: str = Body(None, embed=True),
    content: str = Body(None, embed=True),
    is_active: bool = Body(None, embed=True),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """ویرایش prompt شخصی"""
    repo = AIPromptRepository(db)
    prompt = repo.get_by_id(prompt_id)
    
    if not prompt or prompt.user_id != ctx.get_user_id():
        raise ApiError("PROMPT_NOT_FOUND", "Prompt یافت نشد", http_status=404)
    
    if title is not None:
        prompt.title = title
    if content is not None:
        prompt.content = content
    if is_active is not None:
        prompt.is_active = is_active
    
    db.commit()
    db.refresh(prompt)
    
    return success_response({
        "id": prompt.id,
        "title": prompt.title,
        "content": prompt.content,
        "is_active": prompt.is_active
    }, request, "Prompt با موفقیت به‌روزرسانی شد")


@router.delete("/my/{prompt_id}", summary="حذف prompt شخصی")
async def delete_my_prompt(
    prompt_id: int = Path(...),
    request: Request = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """حذف prompt شخصی"""
    repo = AIPromptRepository(db)
    prompt = repo.get_by_id(prompt_id)
    
    if not prompt or prompt.user_id != ctx.get_user_id():
        raise ApiError("PROMPT_NOT_FOUND", "Prompt یافت نشد", http_status=404)
    
    db.delete(prompt)
    db.commit()
    
    return success_response({"id": prompt_id}, request, "Prompt با موفقیت حذف شد")

