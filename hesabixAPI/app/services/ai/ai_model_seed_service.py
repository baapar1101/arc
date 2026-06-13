from __future__ import annotations

import re
from typing import Any, Dict, List

from sqlalchemy.orm import Session

from adapters.db.models.ai_model import AIModel
from adapters.db.repositories.ai_config_repository import AIConfigRepository
from adapters.db.repositories.ai_model_repository import AIModelRepository

_MODEL_CODE_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{0,78}$", re.I)

_PROVIDER_PRESETS: Dict[str, List[Dict[str, Any]]] = {
    "openai": [
        {
            "code": "gpt-4o-mini",
            "display_name": "GPT-4o Mini",
            "model_id": "gpt-4o-mini",
            "tier": "basic",
            "sort_order": 10,
        },
        {
            "code": "gpt-4o",
            "display_name": "GPT-4o",
            "model_id": "gpt-4o",
            "tier": "pro",
            "sort_order": 20,
        },
        {
            "code": "gpt-4-turbo",
            "display_name": "GPT-4 Turbo",
            "model_id": "gpt-4-turbo",
            "tier": "pro",
            "sort_order": 30,
        },
    ],
    "anthropic": [
        {
            "code": "claude-3-5-haiku",
            "display_name": "Claude 3.5 Haiku",
            "model_id": "claude-3-5-haiku-20241022",
            "tier": "basic",
            "sort_order": 10,
        },
        {
            "code": "claude-3-5-sonnet",
            "display_name": "Claude 3.5 Sonnet",
            "model_id": "claude-3-5-sonnet-20241022",
            "tier": "pro",
            "sort_order": 20,
        },
    ],
    "local": [
        {
            "code": "local-default",
            "display_name": "مدل محلی پیش‌فرض",
            "model_id": "llama3",
            "tier": "basic",
            "sort_order": 10,
            "supports_tools": False,
        },
    ],
}


def normalize_model_code(model_name: str) -> str:
    raw = (model_name or "").strip().lower()
    raw = re.sub(r"[^a-z0-9._-]+", "-", raw)
    raw = re.sub(r"-{2,}", "-", raw).strip("-")
    if not raw or not _MODEL_CODE_RE.match(raw):
        return "default-model"
    return raw[:80]


def _add_model_if_missing(repo: AIModelRepository, db: Session, **fields: Any) -> bool:
    code = str(fields["code"])
    if repo.get_by_code(code):
        return False
    db.add(
        AIModel(
            code=code,
            display_name=str(fields.get("display_name") or code),
            description=fields.get("description"),
            provider=str(fields.get("provider") or "openai"),
            model_id=str(fields.get("model_id") or code),
            tier=fields.get("tier"),
            supports_tools=bool(fields.get("supports_tools", True)),
            max_tokens_default=int(fields.get("max_tokens_default") or 4000),
            is_active=bool(fields.get("is_active", True)),
            sort_order=int(fields.get("sort_order") or 0),
        )
    )
    return True


def seed_models_from_config(
    db: Session,
    *,
    include_presets: bool = True,
    force: bool = False,
) -> Dict[str, Any]:
    """
    اگر کاتالوگ خالی باشد (یا force=True):
    - مدل فعال `ai_configs` را اضافه می‌کند
    - presetهای provider مربوطه را اضافه می‌کند
    """
    repo = AIModelRepository(db)
    existing = db.query(AIModel).count()
    if existing > 0 and not force:
        return {
            "created": 0,
            "skipped": True,
            "reason": "catalog_not_empty",
            "existing_count": existing,
        }

    config_repo = AIConfigRepository(db)
    config = config_repo.get_active_config()
    created: List[str] = []

    if config and config.model_name:
        code = normalize_model_code(config.model_name)
        if _add_model_if_missing(
            repo,
            db,
            code=code,
            display_name=config.model_name,
            provider=config.provider,
            model_id=config.model_name,
            max_tokens_default=int(config.max_tokens or 4000),
            sort_order=0,
            description="ایجاد خودکار از تنظیمات AI",
        ):
            created.append(code)

    if include_presets:
        providers = [config.provider] if config else list(_PROVIDER_PRESETS.keys())
        for provider in providers:
            for preset in _PROVIDER_PRESETS.get(provider, []):
                payload = dict(preset)
                payload["provider"] = provider
                if _add_model_if_missing(repo, db, **payload):
                    created.append(str(payload["code"]))

    if created:
        db.commit()

    return {
        "created": len(created),
        "codes": created,
        "skipped": False,
        "include_presets": include_presets,
        "force": force,
    }
