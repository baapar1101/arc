from __future__ import annotations

import logging
from typing import Any, Dict, Optional, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.ai_config import AIConfig
from adapters.db.models.ai_provider_credential import AIProviderCredential
from adapters.db.repositories.ai_provider_credential_repository import (
    AIProviderCredentialRepository,
)
from app.core.responses import ApiError
from app.services.ai.encryption import decrypt_api_key, encrypt_api_key

logger = logging.getLogger(__name__)

_PROVIDER_LABELS = {
    "openai": "OpenAI",
    "anthropic": "Anthropic",
    "local": "Local / Ollama",
    "custom": "Custom Gateway",
}


def provider_display_name(provider: str) -> str:
    return _PROVIDER_LABELS.get(provider, provider)


def serialize_credential(cred: AIProviderCredential) -> Dict[str, Any]:
    return {
        "id": cred.id,
        "provider": cred.provider,
        "display_name": cred.display_name,
        "api_base_url": cred.api_base_url,
        "api_key": "***" if cred.api_key else None,
        "is_active": cred.is_active,
        "function_calling_enabled": cred.function_calling_enabled,
        "created_at": cred.created_at.isoformat() if cred.created_at else None,
        "updated_at": cred.updated_at.isoformat() if cred.updated_at else None,
    }


def upsert_credential_from_legacy_config(db: Session, config: AIConfig) -> AIProviderCredential:
    """همگام‌سازی credential از رکورد legacy `ai_configs`."""
    repo = AIProviderCredentialRepository(db)
    cred = repo.get_by_provider(config.provider)
    if cred:
        cred.display_name = provider_display_name(config.provider)
        cred.api_base_url = config.api_base_url
        if config.api_key:
            cred.api_key = config.api_key
        cred.is_active = bool(config.is_active)
        cred.function_calling_enabled = bool(getattr(config, "function_calling_enabled", True))
    else:
        cred = AIProviderCredential(
            provider=config.provider,
            display_name=provider_display_name(config.provider),
            api_base_url=config.api_base_url,
            api_key=config.api_key,
            is_active=bool(config.is_active),
            function_calling_enabled=bool(getattr(config, "function_calling_enabled", True)),
        )
        db.add(cred)
    db.flush()
    return cred


def resolve_provider_connection(
    db: Session,
    provider_type: str,
    *,
    legacy_config: Optional[AIConfig] = None,
) -> Tuple[str, str, Optional[str], bool]:
    """
    برگرداندن: (provider_type, api_key_plain, api_base_url, function_calling_enabled)
    """
    repo = AIProviderCredentialRepository(db)
    cred = repo.get_active_by_provider(provider_type)
    if cred and cred.api_key:
        api_key = decrypt_api_key(cred.api_key)
        if api_key:
            return (
                provider_type,
                api_key,
                cred.api_base_url,
                bool(cred.function_calling_enabled),
            )

    if legacy_config and legacy_config.provider == provider_type and legacy_config.api_key:
        api_key = decrypt_api_key(legacy_config.api_key)
        if api_key:
            return (
                provider_type,
                api_key,
                legacy_config.api_base_url,
                bool(getattr(legacy_config, "function_calling_enabled", True)),
            )

    raise ApiError(
        "PROVIDER_CREDENTIAL_NOT_FOUND",
        f"اعتبارنامه provider «{provider_display_name(provider_type)}» تنظیم نشده است",
        http_status=400,
    )


def create_or_update_credential(
    db: Session,
    provider: str,
    *,
    display_name: Optional[str] = None,
    api_base_url: Optional[str] = None,
    api_key: Optional[str] = None,
    is_active: bool = True,
    function_calling_enabled: bool = True,
) -> AIProviderCredential:
    repo = AIProviderCredentialRepository(db)
    cred = repo.get_by_provider(provider)
    encrypted = encrypt_api_key(api_key) if api_key else None
    if cred:
        cred.display_name = display_name or cred.display_name or provider_display_name(provider)
        if api_base_url is not None:
            cred.api_base_url = api_base_url or None
        if encrypted:
            cred.api_key = encrypted
        cred.is_active = is_active
        cred.function_calling_enabled = function_calling_enabled
    else:
        cred = AIProviderCredential(
            provider=provider,
            display_name=display_name or provider_display_name(provider),
            api_base_url=api_base_url or None,
            api_key=encrypted,
            is_active=is_active,
            function_calling_enabled=function_calling_enabled,
        )
        db.add(cred)
    db.commit()
    db.refresh(cred)
    return cred
