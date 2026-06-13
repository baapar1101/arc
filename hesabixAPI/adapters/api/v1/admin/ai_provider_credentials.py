from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, Path, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import ApiError, success_response
from app.services.ai.ai_provider_service import (
    create_or_update_credential,
    provider_display_name,
    resolve_provider_connection,
    serialize_credential,
    upsert_credential_from_legacy_config,
)
from adapters.db.repositories.ai_provider_credential_repository import (
    AIProviderCredentialRepository,
)
from adapters.db.repositories.ai_config_repository import AIConfigRepository
from app.services.ai.ai_provider import create_provider

router = APIRouter(prefix="/admin/ai/provider-credentials", tags=["admin-ai-providers"])


def _require_admin(ctx: AuthContext) -> None:
    if not ctx.has_any_permission("system_settings", "superadmin"):
        raise ApiError("FORBIDDEN", "فقط مدیر سیستم می‌تواند credentialها را مدیریت کند", http_status=403)


@router.get("", summary="لیست credentialهای provider")
async def list_provider_credentials(
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    repo = AIProviderCredentialRepository(db)
    items = [serialize_credential(c) for c in repo.get_all()]
    return success_response(items, request)


@router.put("/{provider}", summary="ایجاد/ویرایش credential provider")
async def upsert_provider_credential(
    provider: str = Path(...),
    request: Request = None,
    payload: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    cred = create_or_update_credential(
        db,
        provider.strip().lower(),
        display_name=payload.get("display_name") or provider_display_name(provider),
        api_base_url=payload.get("api_base_url"),
        api_key=payload.get("api_key"),
        is_active=bool(payload.get("is_active", True)),
        function_calling_enabled=bool(payload.get("function_calling_enabled", True)),
    )
    return success_response(serialize_credential(cred), request, "credential ذخیره شد")


@router.post("/sync-from-config", summary="همگام‌سازی از تنظیمات legacy")
async def sync_credentials_from_config(
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    config = AIConfigRepository(db).get_active_config()
    if not config:
        raise ApiError("CONFIG_NOT_FOUND", "تنظیمات AI فعالی وجود ندارد", http_status=400)
    cred = upsert_credential_from_legacy_config(db, config)
    db.commit()
    db.refresh(cred)
    return success_response(serialize_credential(cred), request, "همگام‌سازی انجام شد")


@router.post("/{provider}/test-connection", summary="تست اتصال provider")
async def test_provider_connection(
    provider: str = Path(...),
    request: Request = None,
    model: Optional[str] = Body(None, embed=True),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_admin(ctx)
    legacy = AIConfigRepository(db).get_active_config()
    ptype, api_key, api_base_url, _ = resolve_provider_connection(
        db, provider.strip().lower(), legacy_config=legacy
    )
    test_model = model or (legacy.model_name if legacy else "gpt-4o-mini")
    provider_client = create_provider(
        provider_type=ptype,
        api_key=api_key,
        api_base_url=api_base_url,
    )
    provider_client.chat_completion(
        messages=[{"role": "user", "content": "سلام"}],
        model=test_model,
        max_tokens=8,
        temperature=0.2,
    )
    return success_response(
        {"success": True, "provider": ptype, "model": test_model},
        request,
        "اتصال برقرار شد",
    )
