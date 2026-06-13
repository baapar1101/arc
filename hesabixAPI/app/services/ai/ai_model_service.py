from __future__ import annotations

import json
import logging
from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.ai_config import AIConfig
from adapters.db.models.ai_model import AIModel
from adapters.db.models.ai_plan import AIPlan
from adapters.db.models.ai_subscription import UserAISubscription
from adapters.db.repositories.ai_model_repository import AIModelRepository
from app.core.responses import ApiError
from app.services.ai.ai_constants import (
    AI_OPERATION_CHAT,
    AUTO_MODEL_CODE,
    LIGHT_AI_OPERATIONS,
)

logger = logging.getLogger(__name__)


def _load_pricing_config(plan: Optional[AIPlan]) -> Dict[str, Any]:
    if not plan or not plan.pricing_config:
        return {}
    try:
        return json.loads(plan.pricing_config)
    except Exception:
        return {}


def get_plan_allowed_model_codes(plan: Optional[AIPlan]) -> Optional[List[str]]:
    """None یعنی همه مدل‌های فعال مجاز هستند."""
    if not plan:
        return None
    pricing = _load_pricing_config(plan)
    allowed = pricing.get("allowed_models")
    if allowed is None:
        return None
    if not isinstance(allowed, list):
        return None
    codes = [str(c).strip() for c in allowed if str(c).strip()]
    return codes or None


def get_plan_default_model_code(plan: Optional[AIPlan]) -> Optional[str]:
    if not plan:
        return None
    pricing = _load_pricing_config(plan)
    default = pricing.get("default_model")
    if default and str(default).strip():
        return str(default).strip()
    return None


def get_model_pricing_rates(
    plan: Optional[AIPlan],
    model_code: str,
) -> Tuple[Decimal, Decimal]:
    """
    نرخ به ازای هر توکن (نه هر ۱۰۰۰ توکن) برای ورودی و خروجی.
    اولویت: pricing_config.pay_as_go.models[code] سپس default سپس pay_as_go سراسری.
    """
    pricing = _load_pricing_config(plan)
    pay_cfg = pricing.get("pay_as_go") or {}
    if not isinstance(pay_cfg, dict):
        pay_cfg = {}

    model_rates = (pay_cfg.get("models") or {}).get(model_code)
    if isinstance(model_rates, dict):
        in_1k = model_rates.get("price_per_1k_input_tokens")
        out_1k = model_rates.get("price_per_1k_output_tokens")
    else:
        default_rates = pay_cfg.get("default")
        if isinstance(default_rates, dict):
            in_1k = default_rates.get("price_per_1k_input_tokens")
            out_1k = default_rates.get("price_per_1k_output_tokens")
        else:
            in_1k = pay_cfg.get("price_per_1k_input_tokens")
            out_1k = pay_cfg.get("price_per_1k_output_tokens")

    input_price = Decimal(str(in_1k or 0)) / Decimal("1000")
    output_price = Decimal(str(out_1k or 0)) / Decimal("1000")
    return input_price, output_price


def calculate_usage_cost(
    plan: Optional[AIPlan],
    model_code: str,
    input_tokens: int,
    output_tokens: int,
    *,
    extra_tokens: Optional[int] = None,
) -> Decimal:
    from app.services.ai.ai_quota_helpers import split_tokens_proportionally

    input_price, output_price = get_model_pricing_rates(plan, model_code)
    if extra_tokens and extra_tokens > 0:
        over_in, over_out = split_tokens_proportionally(
            input_tokens, output_tokens, int(extra_tokens)
        )
        return (Decimal(over_in) * input_price) + (Decimal(over_out) * output_price)
    return (Decimal(input_tokens) * input_price) + (Decimal(output_tokens) * output_price)


def estimate_cost_for_tokens(
    plan: Optional[AIPlan],
    model_code: str,
    estimated_tokens: int,
) -> Decimal:
    """تخمین هزینه با فرض نیمی ورودی و نیمی خروجی."""
    input_price, output_price = get_model_pricing_rates(plan, model_code)
    half = Decimal(estimated_tokens) / Decimal("2")
    return (half * input_price) + (half * output_price)


def is_model_allowed_for_plan(
    db: Session,
    plan: Optional[AIPlan],
    model_code: str,
) -> bool:
    allowed_codes = get_plan_allowed_model_codes(plan)
    if allowed_codes is None:
        repo = AIModelRepository(db)
        model = repo.get_by_code(model_code)
        return model is not None and model.is_active
    return model_code in allowed_codes


def is_auto_model_code(model_code: Optional[str]) -> bool:
    return bool(model_code and str(model_code).strip().lower() == AUTO_MODEL_CODE)


def get_routing_config(plan: Optional[AIPlan]) -> Dict[str, Any]:
    pricing = _load_pricing_config(plan)
    routing = pricing.get("routing")
    if isinstance(routing, dict):
        return routing
    return {}


def _allowed_active_models(db: Session, plan: Optional[AIPlan]) -> List[AIModel]:
    repo = AIModelRepository(db)
    allowed_codes = get_plan_allowed_model_codes(plan)
    if allowed_codes is not None:
        return repo.get_by_codes(allowed_codes, only_active=True)
    return repo.get_active_models()


def is_auto_routing_available(db: Session, plan: Optional[AIPlan]) -> bool:
    """آیا گزینه auto برای این پلن قابل ارائه است."""
    if not plan:
        return False
    pricing = _load_pricing_config(plan)
    allowed_codes = get_plan_allowed_model_codes(plan)
    if allowed_codes and AUTO_MODEL_CODE in allowed_codes:
        return True
    if pricing.get("default_model") == AUTO_MODEL_CODE:
        return True
    routing = get_routing_config(plan)
    if routing.get("enabled") is True:
        return True
    models = _allowed_active_models(db, plan)
    tiers = {m.tier for m in models if m.tier}
    return "basic" in tiers and "pro" in tiers


def _pick_model_from_candidates(
    models: List[AIModel],
    *,
    tier: str,
    needs_tools: bool,
    preferred_code: Optional[str] = None,
) -> Optional[str]:
    if preferred_code and preferred_code != AUTO_MODEL_CODE:
        for m in models:
            if m.code == preferred_code:
                if needs_tools and not m.supports_tools:
                    break
                return m.code

    tier_models = [m for m in models if (m.tier or "basic") == tier]
    if not tier_models:
        tier_models = list(models)

    if needs_tools:
        with_tools = [m for m in tier_models if m.supports_tools]
        if with_tools:
            tier_models = with_tools

    if not tier_models:
        return None
    tier_models.sort(key=lambda m: (m.sort_order, m.id))
    return tier_models[0].code


def resolve_auto_model(
    db: Session,
    plan: Optional[AIPlan],
    *,
    operation: str = AI_OPERATION_CHAT,
    user_query: Optional[str] = None,
    history_messages: Optional[List[dict]] = None,
    needs_tools: bool = False,
) -> str:
    """
    انتخاب مدل واقعی وقتی کاربر/پلن «auto» را انتخاب کرده است.
    """
    from app.services.ai.ai_tool_intent import estimate_query_complexity

    routing = get_routing_config(plan)
    models = _allowed_active_models(db, plan)
    if not models:
        raise ApiError("NO_AI_MODEL", "مدل هوش مصنوعی در دسترس نیست", http_status=400)

    light_code = routing.get("light_model")
    standard_code = routing.get("standard_model")
    power_code = routing.get("power_model")

    if operation in LIGHT_AI_OPERATIONS:
        picked = _pick_model_from_candidates(
            models,
            tier="basic",
            needs_tools=False,
            preferred_code=str(light_code).strip() if light_code else None,
        )
        if picked:
            return picked

    if operation != AI_OPERATION_CHAT:
        picked = _pick_model_from_candidates(
            models,
            tier="basic",
            needs_tools=needs_tools,
            preferred_code=str(light_code).strip() if light_code else None,
        )
        if picked:
            return picked

    complexity = estimate_query_complexity(user_query, history_messages)
    if complexity == "complex" or (complexity == "medium" and needs_tools):
        picked = _pick_model_from_candidates(
            models,
            tier="pro",
            needs_tools=needs_tools,
            preferred_code=str(power_code).strip() if power_code else None,
        )
        if picked:
            return picked

    picked = _pick_model_from_candidates(
        models,
        tier="basic",
        needs_tools=needs_tools,
        preferred_code=str(standard_code).strip() if standard_code else None,
    )
    if picked:
        return picked

    return models[0].code


def resolve_requested_model_code(
    db: Session,
    *,
    request_model: Optional[str],
    subscription: Optional[UserAISubscription],
    plan: Optional[AIPlan],
    config: Optional[AIConfig],
) -> str:
    """
    کد مدل انتخاب‌شده (ممکن است «auto») بدون resolve کردن auto به مدل واقعی.
    """
    candidates: List[Optional[str]] = []
    if request_model and str(request_model).strip():
        candidates.append(str(request_model).strip())
    if subscription and getattr(subscription, "preferred_model_code", None):
        candidates.append(str(subscription.preferred_model_code).strip())
    plan_default = get_plan_default_model_code(plan)
    if plan_default:
        candidates.append(plan_default)
    if config and config.model_name:
        candidates.append(config.model_name.strip())

    repo = AIModelRepository(db)
    active_models = {m.code: m for m in repo.get_active_models()}

    for code in candidates:
        if not code:
            continue
        if is_auto_model_code(code):
            if is_auto_routing_available(db, plan):
                return AUTO_MODEL_CODE
            continue
        if code in active_models and is_model_allowed_for_plan(db, plan, code):
            return code
        if is_model_allowed_for_plan(db, plan, code):
            return code

    if active_models:
        allowed_codes = get_plan_allowed_model_codes(plan)
        if allowed_codes:
            for code in allowed_codes:
                if is_auto_model_code(code) and is_auto_routing_available(db, plan):
                    return AUTO_MODEL_CODE
                if code in active_models:
                    return code
        first = next(iter(active_models.values()))
        return first.code

    if config and config.model_name:
        return config.model_name
    raise ApiError("NO_AI_MODEL", "مدل هوش مصنوعی در دسترس نیست", http_status=400)


def resolve_effective_model_code(
    db: Session,
    *,
    request_model: Optional[str],
    subscription: Optional[UserAISubscription],
    plan: Optional[AIPlan],
    config: Optional[AIConfig],
    operation: str = AI_OPERATION_CHAT,
    user_query: Optional[str] = None,
    history_messages: Optional[List[dict]] = None,
    needs_tools: bool = False,
) -> str:
    """
    ترتیب اولویت:
    request_model → subscription.preferred_model_code → plan.default_model → config.model_name
    اگر نتیجه «auto» باشد، بر اساس operation و پیچیدگی resolve می‌شود.
    """
    selected = resolve_requested_model_code(
        db,
        request_model=request_model,
        subscription=subscription,
        plan=plan,
        config=config,
    )
    if is_auto_model_code(selected):
        return resolve_auto_model(
            db,
            plan,
            operation=operation,
            user_query=user_query,
            history_messages=history_messages,
            needs_tools=needs_tools,
        )
    return selected


def resolve_model_record(
    db: Session,
    model_code: str,
) -> Optional[AIModel]:
    repo = AIModelRepository(db)
    return repo.get_by_code(model_code)


def get_api_model_id(db: Session, model_code: str, config: Optional[AIConfig]) -> str:
    record = resolve_model_record(db, model_code)
    if record:
        return record.model_id
    if config and config.model_name == model_code:
        return config.model_name
    return model_code


def get_model_provider(db: Session, model_code: str, config: Optional[AIConfig]) -> str:
    record = resolve_model_record(db, model_code)
    if record:
        return record.provider
    if config:
        return config.provider
    return "openai"


def model_supports_tools(
    db: Session,
    model_code: str,
    config: Optional[AIConfig],
) -> bool:
    from app.services.ai.ai_provider_service import resolve_provider_connection

    record = resolve_model_record(db, model_code)
    provider_type = record.provider if record else (config.provider if config else "openai")
    try:
        _, _, _, fce = resolve_provider_connection(db, provider_type, legacy_config=config)
        if not fce:
            return False
    except Exception:
        if config and getattr(config, "function_calling_enabled", True) is False:
            return False
    if record:
        return bool(record.supports_tools)
    if config:
        return bool(getattr(config, "function_calling_enabled", True))
    return True


def get_max_tokens_for_model(
    db: Session,
    model_code: str,
    config: Optional[AIConfig],
) -> int:
    record = resolve_model_record(db, model_code)
    if record and record.max_tokens_default:
        return int(record.max_tokens_default)
    if config:
        return int(config.max_tokens)
    return 4000


def estimate_auto_cost_range(
    plan: Optional[AIPlan],
    db: Session,
    estimated_tokens: int,
) -> Dict[str, Any]:
    """تخمین بازه هزینه برای مدل auto (ارزان‌ترین تا گران‌ترین مجاز)."""
    models = _allowed_active_models(db, plan)
    if not models:
        return {"min": 0.0, "max": 0.0, "likely_model": None}

    basic_models = [m for m in models if (m.tier or "basic") == "basic"]
    pro_models = [m for m in models if m.tier == "pro"]
    cheap = basic_models[0] if basic_models else models[0]
    expensive = pro_models[-1] if pro_models else models[-1]

    min_cost = float(estimate_cost_for_tokens(plan, cheap.code, estimated_tokens))
    max_cost = float(estimate_cost_for_tokens(plan, expensive.code, estimated_tokens))
    return {
        "min": min_cost,
        "max": max_cost,
        "likely_model": cheap.code,
        "likely_model_display": cheap.display_name,
    }


def build_auto_catalog_item(plan: Optional[AIPlan], db: Session) -> Dict[str, Any]:
    """آیتم synthetic برای dropdown مدل."""
    cost_range = estimate_auto_cost_range(plan, db, 1000)
    min_c = cost_range["min"]
    max_c = cost_range["max"]
    if min_c <= 0 and max_c <= 0:
        hint = "شامل سهمیه / بهینه‌سازی خودکار هزینه"
    elif abs(min_c - max_c) < 0.01:
        hint = f"حدود {min_c:,.0f} / ۱۰۰۰ توکن"
    else:
        hint = f"از {min_c:,.0f} تا {max_c:,.0f} / ۱۰۰۰ توکن (بسته به پیچیدگی)"

    return {
        "id": None,
        "code": AUTO_MODEL_CODE,
        "display_name": "خودکار (Auto)",
        "description": "کارهای سبک با مدل ارزان و سوالات پیچیده با مدل قوی‌تر",
        "provider": "auto",
        "model_id": AUTO_MODEL_CODE,
        "tier": None,
        "supports_tools": True,
        "max_tokens_default": 4000,
        "reference_input_cost_per_1k": None,
        "reference_output_cost_per_1k": None,
        "is_active": True,
        "sort_order": -100,
        "is_default": get_plan_default_model_code(plan) == AUTO_MODEL_CODE,
        "created_at": None,
        "updated_at": None,
        "pricing_hint": hint,
        "estimated_cost_per_1k_tokens": min_c,
        "is_auto": True,
    }


def list_models_for_user(
    db: Session,
    plan: Optional[AIPlan],
    *,
    include_pricing: bool = True,
) -> List[Dict[str, Any]]:
    repo = AIModelRepository(db)
    allowed_codes = get_plan_allowed_model_codes(plan)
    if allowed_codes is not None:
        models = repo.get_by_codes(allowed_codes, only_active=True)
    else:
        models = repo.get_active_models()

    default_code = get_plan_default_model_code(plan)
    result: List[Dict[str, Any]] = []

    if is_auto_routing_available(db, plan):
        auto_item = build_auto_catalog_item(plan, db)
        if include_pricing and plan:
            cost_range = estimate_auto_cost_range(plan, db, 1000)
            auto_item["pricing"] = {
                "estimated_cost_min": cost_range["min"],
                "estimated_cost_max": cost_range["max"],
            }
        result.append(auto_item)

    for m in models:
        item = serialize_model(m, default=(default_code == m.code))
        if include_pricing and plan:
            in_1k, out_1k = get_model_pricing_rates(plan, m.code)
            item["pricing"] = {
                "price_per_1k_input_tokens": float(in_1k * 1000),
                "price_per_1k_output_tokens": float(out_1k * 1000),
            }
            est = estimate_cost_for_tokens(plan, m.code, 1000)
            item["estimated_cost_per_1k_tokens"] = float(est)
            item["pricing_hint"] = _format_pricing_hint(
                float(in_1k * 1000), float(out_1k * 1000), float(est)
            )
        elif include_pricing:
            item["pricing_hint"] = "بر اساس پلن اشتراک"
        result.append(item)
    return result


def _format_pricing_hint(
    input_per_1k: float,
    output_per_1k: float,
    estimated_per_1k: float,
) -> str:
    if input_per_1k <= 0 and output_per_1k <= 0:
        return "شامل سهمیه / بدون هزینه اضافه"
    if abs(input_per_1k - output_per_1k) < 0.0001:
        return f"حدود {estimated_per_1k:,.0f} / ۱۰۰۰ توکن"
    return (
        f"ورودی {input_per_1k:,.0f} — خروجی {output_per_1k:,.0f} (هر ۱k) · "
        f"تخمین ~{estimated_per_1k:,.0f}"
    )


def serialize_model(model: AIModel, *, default: bool = False) -> Dict[str, Any]:
    return {
        "id": model.id,
        "code": model.code,
        "display_name": model.display_name,
        "description": model.description,
        "provider": model.provider,
        "model_id": model.model_id,
        "tier": model.tier,
        "supports_tools": model.supports_tools,
        "max_tokens_default": model.max_tokens_default,
        "reference_input_cost_per_1k": float(model.reference_input_cost_per_1k)
        if model.reference_input_cost_per_1k is not None
        else None,
        "reference_output_cost_per_1k": float(model.reference_output_cost_per_1k)
        if model.reference_output_cost_per_1k is not None
        else None,
        "is_active": model.is_active,
        "sort_order": model.sort_order,
        "is_default": default,
        "created_at": model.created_at.isoformat() if model.created_at else None,
        "updated_at": model.updated_at.isoformat() if model.updated_at else None,
    }


def validate_model_selection(
    db: Session,
    plan: Optional[AIPlan],
    model_code: str,
) -> Optional[AIModel]:
    if is_auto_model_code(model_code):
        if not is_auto_routing_available(db, plan):
            raise ApiError(
                "MODEL_NOT_ALLOWED",
                "مدل خودکار در پلن فعلی شما مجاز نیست",
                http_status=403,
            )
        return None
    repo = AIModelRepository(db)
    model = repo.get_by_code(model_code)
    if not model or not model.is_active:
        raise ApiError("MODEL_NOT_FOUND", "مدل انتخاب‌شده یافت نشد یا غیرفعال است", http_status=400)
    if not is_model_allowed_for_plan(db, plan, model_code):
        raise ApiError(
            "MODEL_NOT_ALLOWED",
            "مدل انتخاب‌شده در پلن فعلی شما مجاز نیست",
            http_status=403,
        )
    return model


def serialize_plan_for_user(plan: AIPlan) -> Dict[str, Any]:
    pricing = _load_pricing_config(plan)
    try:
        usage_limits = json.loads(plan.usage_limits or "{}")
    except Exception:
        usage_limits = {}
    try:
        features = json.loads(plan.features or "{}")
    except Exception:
        features = {}
    return {
        "id": plan.id,
        "code": plan.code,
        "name": plan.name,
        "description": plan.description,
        "plan_type": plan.plan_type,
        "pricing_config": pricing,
        "usage_limits": usage_limits,
        "features": features,
        "tokens_limit": plan.tokens_limit,
        "monthly_tokens_limit": plan.monthly_tokens_limit,
        "default_model": pricing.get("default_model"),
        "allowed_models": pricing.get("allowed_models"),
        "is_active": plan.is_active,
        "auto_renew": plan.auto_renew,
    }
