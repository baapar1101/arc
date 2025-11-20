from __future__ import annotations

from typing import Dict, Any
from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from adapters.db.repositories.ai_config_repository import AIConfigRepository
from adapters.db.models.ai_config import AIConfig, AIProvider
from pydantic import BaseModel

router = APIRouter(prefix="/admin/ai", tags=["admin-ai"])


class AIConfigRequest(BaseModel):
    provider: str
    model_name: str
    api_base_url: str | None = None
    api_key: str | None = None
    max_tokens: int = 4000
    temperature: float = 0.7
    is_active: bool = True


@router.get("/config", summary="دریافت تنظیمات AI")
async def get_ai_config(
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """دریافت تنظیمات AI (فقط مدیر سیستم)"""
    if not ctx.is_superadmin():
        raise ApiError("FORBIDDEN", "فقط مدیر سیستم می‌تواند تنظیمات AI را مشاهده کند", http_status=403)
    
    repo = AIConfigRepository(db)
    config = repo.get_active_config()
    
    if not config:
        return success_response({
            "provider": "openai",
            "model_name": "gpt-4",
            "api_base_url": None,
            "api_key": None,
            "max_tokens": 4000,
            "temperature": 0.7,
            "is_active": False
        }, request)
    
    return success_response({
        "id": config.id,
        "provider": config.provider,
        "model_name": config.model_name,
        "api_base_url": config.api_base_url,
        "api_key": "***" if config.api_key else None,  # مخفی کردن API key
        "max_tokens": config.max_tokens,
        "temperature": float(config.temperature),
        "is_active": config.is_active
    }, request)


@router.put("/config", summary="به‌روزرسانی تنظیمات AI")
async def update_ai_config(
    request: Request,
    config_data: AIConfigRequest = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """به‌روزرسانی تنظیمات AI (فقط مدیر سیستم)"""
    if not ctx.is_superadmin():
        raise ApiError("FORBIDDEN", "فقط مدیر سیستم می‌تواند تنظیمات AI را تغییر دهد", http_status=403)
    
    repo = AIConfigRepository(db)
    config = repo.get_active_config()
    
    from app.services.ai.encryption import encrypt_api_key
    
    if config:
        config.provider = config_data.provider
        config.model_name = config_data.model_name
        config.api_base_url = config_data.api_base_url
        if config_data.api_key:
            # رمزگذاری API key
            config.api_key = encrypt_api_key(config_data.api_key)
        config.max_tokens = config_data.max_tokens
        config.temperature = config_data.temperature
        config.is_active = config_data.is_active
    else:
        from app.services.ai.encryption import encrypt_api_key
        encrypted_key = encrypt_api_key(config_data.api_key) if config_data.api_key else None
        config = AIConfig(
            provider=config_data.provider,
            model_name=config_data.model_name,
            api_base_url=config_data.api_base_url,
            api_key=encrypted_key,
            max_tokens=config_data.max_tokens,
            temperature=config_data.temperature,
            is_active=config_data.is_active
        )
        db.add(config)
    
    db.commit()
    db.refresh(config)
    
    return success_response({
        "id": config.id,
        "provider": config.provider,
        "model_name": config.model_name,
        "api_base_url": config.api_base_url,
        "api_key": "***" if config.api_key else None,
        "max_tokens": config.max_tokens,
        "temperature": float(config.temperature),
        "is_active": config.is_active
    }, request)


@router.post("/config/test-connection", summary="تست اتصال به AI Provider")
async def test_ai_connection(
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """تست اتصال به AI Provider (فقط مدیر سیستم)"""
    if not ctx.is_superadmin():
        raise ApiError("FORBIDDEN", "فقط مدیر سیستم می‌تواند اتصال را تست کند", http_status=403)
    
    repo = AIConfigRepository(db)
    config = repo.get_active_config()
    
    if not config or not config.is_active:
        raise ApiError("CONFIG_NOT_FOUND", "تنظیمات AI فعالی وجود ندارد", http_status=400)
    
    # رمزگشایی API Key
    from app.services.ai.encryption import decrypt_api_key
    api_key = decrypt_api_key(config.api_key) if config.api_key else None
    
    if not api_key:
        raise ApiError("API_KEY_NOT_SET", "API Key تنظیم نشده است", http_status=400)
    
    # تست اتصال
    try:
        from app.services.ai.ai_provider import create_provider
        provider = create_provider(
            provider_type=config.provider,
            api_key=api_key,
            api_base_url=config.api_base_url
        )
        
        # ارسال یک درخواست تست
        test_response = provider.chat_completion(
            messages=[{"role": "user", "content": "سلام"}],
            model=config.model_name,
            max_tokens=10,
            temperature=0.7
        )
        
        return success_response({
            "success": True,
            "message": "اتصال با موفقیت برقرار شد",
            "model": config.model_name,
            "provider": config.provider
        }, request)
    except Exception as e:
        logger.error(f"AI connection test failed: {e}", exc_info=True)
        raise ApiError("CONNECTION_FAILED", f"خطا در اتصال: {str(e)}", http_status=400)

