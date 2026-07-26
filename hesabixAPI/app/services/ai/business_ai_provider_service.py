from __future__ import annotations

import ipaddress
import json
import logging
import socket
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urlparse

from sqlalchemy.orm import Session

from adapters.db.models.ai_plan import AIPlan, AIPlanType
from adapters.db.models.business_ai_provider_config import BusinessAIProviderConfig
from adapters.db.repositories.ai_subscription_repository import AISubscriptionRepository
from adapters.db.repositories.business_ai_provider_config_repository import (
    BusinessAIProviderConfigRepository,
)
from app.core.responses import ApiError
from app.services.ai.encryption import decrypt_api_key, encrypt_api_key

logger = logging.getLogger(__name__)

ALLOWED_BYOK_PROVIDERS = frozenset({"openai", "anthropic", "local"})
_MAX_MODELS = 50
_MAX_MODEL_CODE_LEN = 120


def is_byok_plan(plan: Optional[AIPlan]) -> bool:
    return bool(plan and plan.plan_type == AIPlanType.BYOK.value)


def get_byok_pricing(plan: Optional[AIPlan]) -> Dict[str, Any]:
    if not plan or not plan.pricing_config:
        return {}
    try:
        pricing = json.loads(plan.pricing_config)
    except Exception:
        return {}
    if not isinstance(pricing, dict):
        return {}
    return pricing


def get_byok_allowed_providers(plan: Optional[AIPlan]) -> List[str]:
    pricing = get_byok_pricing(plan)
    allowed = pricing.get("allowed_providers")
    if isinstance(allowed, list) and allowed:
        out = [str(p).strip().lower() for p in allowed if str(p).strip()]
        return [p for p in out if p in ALLOWED_BYOK_PROVIDERS] or ["openai"]
    return ["openai", "anthropic"]


def get_byok_platform_fee(plan: Optional[AIPlan]) -> Dict[str, float]:
    """کارمزد پلتفرم برای پلن BYOK (ماهانه/سالانه)."""
    pricing = get_byok_pricing(plan)
    fee = pricing.get("platform_fee") or pricing.get("subscription") or {}
    if not isinstance(fee, dict):
        fee = {}
    try:
        monthly = float(fee.get("monthly_price") or 0)
    except (TypeError, ValueError):
        monthly = 0.0
    try:
        yearly = float(fee.get("yearly_price") or 0)
    except (TypeError, ValueError):
        yearly = 0.0
    return {"monthly_price": monthly, "yearly_price": yearly}


def require_byok_connection_test(plan: Optional[AIPlan]) -> bool:
    pricing = get_byok_pricing(plan)
    if "require_connection_test" in pricing:
        return bool(pricing.get("require_connection_test"))
    return True


def business_has_active_byok_subscription(
    db: Session,
    *,
    user_id: int,
    business_id: int,
) -> Tuple[bool, Optional[AIPlan]]:
    sub = AISubscriptionRepository(db).get_active_subscription(
        user_id=user_id,
        business_id=business_id,
    )
    if not sub or not sub.is_active or not sub.plan:
        return False, None
    if not is_byok_plan(sub.plan):
        return False, sub.plan
    return True, sub.plan


def parse_models_json(raw: Optional[str]) -> List[Dict[str, Any]]:
    if not raw:
        return []
    try:
        data = json.loads(raw)
    except Exception:
        return []
    if not isinstance(data, list):
        return []
    result: List[Dict[str, Any]] = []
    for item in data:
        if not isinstance(item, dict):
            continue
        code = str(item.get("code") or item.get("model_id") or "").strip()
        if not code:
            continue
        display = str(item.get("display_name") or code).strip() or code
        model_id = str(item.get("model_id") or code).strip() or code
        result.append(
            {
                "code": code[:_MAX_MODEL_CODE_LEN],
                "display_name": display[:200],
                "model_id": model_id[:_MAX_MODEL_CODE_LEN],
                "supports_tools": bool(item.get("supports_tools", True)),
                "description": (str(item.get("description") or "").strip() or None),
            }
        )
    return result[:_MAX_MODELS]


def normalize_models_payload(models: Any) -> List[Dict[str, Any]]:
    if models is None:
        return []
    if isinstance(models, str):
        return parse_models_json(models)
    if not isinstance(models, list):
        raise ApiError("INVALID_MODELS", "لیست مدل‌ها نامعتبر است", http_status=400)
    normalized: List[Dict[str, Any]] = []
    seen: set[str] = set()
    for item in models:
        if isinstance(item, str):
            code = item.strip()
            if not code or code in seen:
                continue
            seen.add(code)
            normalized.append(
                {
                    "code": code[:_MAX_MODEL_CODE_LEN],
                    "display_name": code[:200],
                    "model_id": code[:_MAX_MODEL_CODE_LEN],
                    "supports_tools": True,
                    "description": None,
                }
            )
            continue
        if not isinstance(item, dict):
            continue
        code = str(item.get("code") or item.get("model_id") or "").strip()
        if not code or code in seen:
            continue
        seen.add(code)
        display = str(item.get("display_name") or code).strip() or code
        model_id = str(item.get("model_id") or code).strip() or code
        normalized.append(
            {
                "code": code[:_MAX_MODEL_CODE_LEN],
                "display_name": display[:200],
                "model_id": model_id[:_MAX_MODEL_CODE_LEN],
                "supports_tools": bool(item.get("supports_tools", True)),
                "description": (str(item.get("description") or "").strip() or None),
            }
        )
    if len(normalized) > _MAX_MODELS:
        raise ApiError(
            "TOO_MANY_MODELS",
            f"حداکثر {_MAX_MODELS} مدل مجاز است",
            http_status=400,
        )
    return normalized


def validate_api_base_url(url: Optional[str], *, provider: str) -> Optional[str]:
    if url is None:
        return None
    cleaned = str(url).strip()
    if not cleaned:
        if provider == "local":
            raise ApiError(
                "API_BASE_URL_REQUIRED",
                "برای Local/Ollama آدرس پایه الزامی است",
                http_status=400,
            )
        return None
    parsed = urlparse(cleaned)
    if parsed.scheme not in ("http", "https"):
        raise ApiError(
            "INVALID_API_BASE_URL",
            "آدرس پایه باید با http یا https شروع شود",
            http_status=400,
        )
    if not parsed.hostname:
        raise ApiError("INVALID_API_BASE_URL", "آدرس پایه نامعتبر است", http_status=400)
    host = parsed.hostname.lower()
    # Local/Ollama: localhost و شبکه خصوصی مجاز است
    if provider == "local":
        if host == "metadata.google.internal":
            raise ApiError("INVALID_API_BASE_URL", "این میزبان مجاز نیست", http_status=400)
        return cleaned.rstrip("/")
    if host in ("localhost", "127.0.0.1", "::1", "metadata.google.internal"):
        raise ApiError(
            "PRIVATE_API_BASE_URL_BLOCKED",
            "برای OpenAI/Anthropic آدرس localhost مجاز نیست",
            http_status=400,
        )
    try:
        infos = socket.getaddrinfo(host, parsed.port or (443 if parsed.scheme == "https" else 80))
    except socket.gaierror as exc:
        raise ApiError(
            "INVALID_API_BASE_URL",
            f"امکان resolve کردن میزبان وجود ندارد: {host}",
            http_status=400,
        ) from exc
    for info in infos:
        ip_str = info[4][0]
        try:
            ip = ipaddress.ip_address(ip_str)
        except ValueError:
            continue
        if (
            ip.is_private
            or ip.is_loopback
            or ip.is_link_local
            or ip.is_reserved
            or ip.is_multicast
            or ip.is_unspecified
        ):
            raise ApiError(
                "PRIVATE_API_BASE_URL_BLOCKED",
                "آدرس‌های شبکه خصوصی برای این ارائه‌دهنده مجاز نیستند",
                http_status=400,
            )
    return cleaned.rstrip("/")

def get_config(
    db: Session,
    business_id: int,
) -> Optional[BusinessAIProviderConfig]:
    return BusinessAIProviderConfigRepository(db).get_by_business_id(int(business_id))


def config_is_ready(cfg: Optional[BusinessAIProviderConfig], *, require_test: bool = True) -> bool:
    if not cfg or not cfg.is_active:
        return False
    if not cfg.api_key:
        return False
    if cfg.provider == "local" and not (cfg.api_base_url or "").strip():
        return False
    models = parse_models_json(cfg.models_json)
    if not models:
        return False
    if require_test and cfg.last_test_ok is not True:
        return False
    return True


def serialize_config(
    cfg: Optional[BusinessAIProviderConfig],
    *,
    plan: Optional[AIPlan] = None,
) -> Dict[str, Any]:
    if not cfg:
        return {
            "configured": False,
            "is_ready": False,
            "provider": None,
            "display_name": None,
            "api_base_url": None,
            "api_key": None,
            "models": [],
            "default_model": None,
            "function_calling_enabled": True,
            "is_active": False,
            "last_tested_at": None,
            "last_test_ok": None,
            "last_test_error": None,
            "allowed_providers": get_byok_allowed_providers(plan),
            "require_connection_test": require_byok_connection_test(plan),
        }
    models = parse_models_json(cfg.models_json)
    require_test = require_byok_connection_test(plan)
    return {
        "configured": True,
        "is_ready": config_is_ready(cfg, require_test=require_test),
        "id": cfg.id,
        "business_id": cfg.business_id,
        "provider": cfg.provider,
        "display_name": cfg.display_name,
        "api_base_url": cfg.api_base_url,
        "api_key": "***" if cfg.api_key else None,
        "has_api_key": bool(cfg.api_key),
        "models": models,
        "default_model": cfg.default_model,
        "function_calling_enabled": bool(cfg.function_calling_enabled),
        "is_active": bool(cfg.is_active),
        "last_tested_at": cfg.last_tested_at.isoformat() if cfg.last_tested_at else None,
        "last_test_ok": cfg.last_test_ok,
        "last_test_error": cfg.last_test_error,
        "allowed_providers": get_byok_allowed_providers(plan),
        "require_connection_test": require_test,
        "created_at": cfg.created_at.isoformat() if cfg.created_at else None,
        "updated_at": cfg.updated_at.isoformat() if cfg.updated_at else None,
    }


def upsert_config(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    payload: Dict[str, Any],
) -> BusinessAIProviderConfig:
    has_byok, plan = business_has_active_byok_subscription(
        db, user_id=user_id, business_id=business_id
    )
    if not has_byok:
        raise ApiError(
            "BYOK_PLAN_REQUIRED",
            "برای تنظیم ارائه‌دهنده اختصاصی، ابتدا پلن «ارائه‌دهنده اختصاصی» را فعال کنید",
            http_status=400,
        )

    provider = str(payload.get("provider") or "openai").strip().lower()
    allowed = get_byok_allowed_providers(plan)
    if provider not in ALLOWED_BYOK_PROVIDERS:
        raise ApiError("INVALID_PROVIDER", f"ارائه‌دهنده «{provider}» پشتیبانی نمی‌شود", http_status=400)
    if provider not in allowed:
        raise ApiError(
            "PROVIDER_NOT_ALLOWED",
            f"ارائه‌دهنده «{provider}» در پلن فعلی مجاز نیست",
            http_status=400,
        )

    api_base_url = validate_api_base_url(payload.get("api_base_url"), provider=provider)
    models = normalize_models_payload(payload.get("models"))
    if not models:
        raise ApiError("BYOK_NO_MODELS", "حداقل یک مدل باید تعریف شود", http_status=400)

    default_model = str(payload.get("default_model") or "").strip() or None
    model_codes = {m["code"] for m in models}
    if default_model and default_model not in model_codes:
        raise ApiError(
            "INVALID_DEFAULT_MODEL",
            "مدل پیش‌فرض باید در لیست مدل‌ها باشد",
            http_status=400,
        )
    if not default_model:
        default_model = models[0]["code"]

    repo = BusinessAIProviderConfigRepository(db)
    cfg = repo.get_by_business_id(business_id)
    api_key_raw = payload.get("api_key")
    encrypted: Optional[str] = None
    if api_key_raw is not None and str(api_key_raw).strip() and str(api_key_raw).strip() != "***":
        encrypted = encrypt_api_key(str(api_key_raw).strip())

    if cfg:
        cfg.provider = provider
        cfg.display_name = (str(payload.get("display_name") or "").strip() or None)
        cfg.api_base_url = api_base_url
        if encrypted:
            cfg.api_key = encrypted
        elif not cfg.api_key:
            raise ApiError("API_KEY_REQUIRED", "API Key الزامی است", http_status=400)
        cfg.models_json = json.dumps(models, ensure_ascii=False)
        cfg.default_model = default_model
        cfg.function_calling_enabled = bool(payload.get("function_calling_enabled", True))
        cfg.is_active = bool(payload.get("is_active", True))
        # تغییر تنظیمات → نیاز به تست مجدد
        cfg.last_test_ok = None
        cfg.last_test_error = None
        cfg.last_tested_at = None
    else:
        if not encrypted:
            raise ApiError("API_KEY_REQUIRED", "API Key الزامی است", http_status=400)
        cfg = BusinessAIProviderConfig(
            business_id=int(business_id),
            provider=provider,
            display_name=(str(payload.get("display_name") or "").strip() or None),
            api_base_url=api_base_url,
            api_key=encrypted,
            models_json=json.dumps(models, ensure_ascii=False),
            default_model=default_model,
            function_calling_enabled=bool(payload.get("function_calling_enabled", True)),
            is_active=bool(payload.get("is_active", True)),
        )
        db.add(cfg)

    db.commit()
    db.refresh(cfg)
    logger.info(
        "Business AI provider config saved business_id=%s provider=%s models=%s",
        business_id,
        provider,
        len(models),
    )
    return cfg


def delete_config(db: Session, business_id: int) -> None:
    repo = BusinessAIProviderConfigRepository(db)
    cfg = repo.get_by_business_id(business_id)
    if not cfg:
        return
    db.delete(cfg)
    db.commit()


def resolve_byok_connection(
    db: Session,
    business_id: int,
) -> Tuple[str, str, Optional[str], bool]:
    """
    Returns: (provider_type, api_key_plain, api_base_url, function_calling_enabled)
    """
    cfg = get_config(db, business_id)
    if not cfg or not cfg.is_active:
        raise ApiError(
            "BYOK_NOT_CONFIGURED",
            "ارائه‌دهنده اختصاصی برای این کسب‌وکار تنظیم نشده است",
            http_status=400,
        )
    if not cfg.api_key:
        raise ApiError("BYOK_NOT_CONFIGURED", "API Key تنظیم نشده است", http_status=400)
    api_key = decrypt_api_key(cfg.api_key)
    if not api_key:
        raise ApiError(
            "BYOK_KEY_DECRYPT_FAILED",
            "امکان خواندن API Key وجود ندارد؛ لطفاً دوباره ذخیره کنید",
            http_status=400,
        )
    return (
        cfg.provider,
        api_key,
        cfg.api_base_url,
        bool(cfg.function_calling_enabled),
    )


def list_byok_models_for_user(
    db: Session,
    business_id: int,
    plan: Optional[AIPlan] = None,
) -> List[Dict[str, Any]]:
    cfg = get_config(db, business_id)
    if not cfg:
        return []
    models = parse_models_json(cfg.models_json)
    default_code = cfg.default_model
    result: List[Dict[str, Any]] = []
    for idx, m in enumerate(models):
        result.append(
            {
                "id": None,
                "code": m["code"],
                "display_name": m["display_name"],
                "description": m.get("description") or "مدل ارائه‌دهنده اختصاصی",
                "provider": cfg.provider,
                "model_id": m["model_id"],
                "tier": None,
                "supports_tools": bool(m.get("supports_tools", True)),
                "max_tokens_default": 4000,
                "supports_reasoning": False,
                "reasoning_effort": None,
                "reference_input_cost_per_1k": None,
                "reference_output_cost_per_1k": None,
                "is_active": True,
                "sort_order": idx,
                "is_default": (default_code == m["code"]) if default_code else idx == 0,
                "created_at": None,
                "updated_at": None,
                "pricing_hint": "هزینه توسط ارائه‌دهنده شما محاسبه می‌شود",
                "estimated_cost_per_1k_tokens": 0,
                "is_byok": True,
                "pricing": {
                    "price_per_1k_input_tokens": 0,
                    "price_per_1k_output_tokens": 0,
                },
            }
        )
    return result


def is_byok_model_allowed(db: Session, business_id: int, model_code: str) -> bool:
    cfg = get_config(db, business_id)
    if not cfg:
        return False
    codes = {m["code"] for m in parse_models_json(cfg.models_json)}
    return model_code in codes


def get_byok_model_api_id(db: Session, business_id: int, model_code: str) -> str:
    cfg = get_config(db, business_id)
    if not cfg:
        return model_code
    for m in parse_models_json(cfg.models_json):
        if m["code"] == model_code:
            return m["model_id"]
    return model_code


def get_byok_default_model(db: Session, business_id: int) -> Optional[str]:
    cfg = get_config(db, business_id)
    if not cfg:
        return None
    if cfg.default_model:
        return cfg.default_model
    models = parse_models_json(cfg.models_json)
    return models[0]["code"] if models else None


def test_connection(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    model: Optional[str] = None,
) -> Dict[str, Any]:
    has_byok, _plan = business_has_active_byok_subscription(
        db, user_id=user_id, business_id=business_id
    )
    if not has_byok:
        raise ApiError(
            "BYOK_PLAN_REQUIRED",
            "برای تست اتصال، پلن ارائه‌دهنده اختصاصی لازم است",
            http_status=400,
        )

    cfg = get_config(db, business_id)
    if not cfg or not cfg.api_key:
        raise ApiError("BYOK_NOT_CONFIGURED", "ابتدا تنظیمات را ذخیره کنید", http_status=400)

    models = parse_models_json(cfg.models_json)
    if not models:
        raise ApiError("BYOK_NO_MODELS", "حداقل یک مدل باید تعریف شود", http_status=400)

    test_model_code = (model or cfg.default_model or models[0]["code"]).strip()
    api_model_id = get_byok_model_api_id(db, business_id, test_model_code)

    from app.services.ai.ai_provider import create_provider

    ptype, api_key, api_base_url, _ = resolve_byok_connection(db, business_id)
    provider_client = create_provider(
        provider_type=ptype,
        api_key=api_key,
        api_base_url=api_base_url,
    )

    now = datetime.utcnow()
    try:
        provider_client.chat_completion(
            messages=[{"role": "user", "content": "ping"}],
            model=api_model_id,
            max_tokens=8,
            temperature=0.0,
        )
        cfg.last_tested_at = now
        cfg.last_test_ok = True
        cfg.last_test_error = None
        db.commit()
        return {
            "success": True,
            "provider": ptype,
            "model": test_model_code,
            "model_id": api_model_id,
            "tested_at": now.isoformat(),
        }
    except Exception as exc:
        err_msg = str(exc)[:500]
        # هرگز کلید را در خطا ننویس
        cfg.last_tested_at = now
        cfg.last_test_ok = False
        cfg.last_test_error = err_msg
        db.commit()
        logger.warning(
            "BYOK connection test failed business_id=%s provider=%s: %s",
            business_id,
            ptype,
            err_msg,
        )
        raise ApiError(
            "BYOK_TEST_FAILED",
            f"تست اتصال ناموفق بود: {err_msg}",
            http_status=400,
            details={"provider": ptype, "model": test_model_code},
        ) from exc
