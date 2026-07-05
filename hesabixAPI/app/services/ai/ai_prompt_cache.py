"""
Prompt Caching در سطح Provider (OpenAI / Anthropic).

مسئولیت‌ها:
  - تصمیم فعال‌سازی cache بر اساس provider و اندازه prefix
  - تبدیل پیام‌های داخلی به فرمت API با breakpoint
  - نرمال‌سازی usage (cached_tokens, cache_read, cache_creation)
"""
from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any, Dict, List, Optional

from app.services.ai.ai_constants import (
    ANTHROPIC_PROMPT_CACHE_TTL,
    OPENAI_PROMPT_CACHE_RETENTION,
    PROMPT_CACHE_ENABLED,
    PROMPT_CACHE_MIN_STATIC_TOKENS,
)
from app.services.ai.ai_system_prompt import StructuredSystemPrompt

logger = logging.getLogger(__name__)

ANTHROPIC_EPHEMERAL_CACHE = {"type": "ephemeral"}


@dataclass(frozen=True)
class LLMUsageDetails:
    input_tokens: int
    output_tokens: int
    total_tokens: int
    cached_tokens: int = 0
    cache_creation_tokens: int = 0
    cache_read_tokens: int = 0

    def to_usage_dict(self) -> Dict[str, int]:
        return {
            "input_tokens": self.input_tokens,
            "output_tokens": self.output_tokens,
            "total_tokens": self.total_tokens,
            "cached_tokens": self.cached_tokens,
            "cache_creation_input_tokens": self.cache_creation_tokens,
            "cache_read_input_tokens": self.cache_read_tokens,
        }

    def cache_hit_ratio(self) -> float:
        if self.input_tokens <= 0:
            return 0.0
        return min(1.0, self.cache_read_tokens / self.input_tokens)


@dataclass(frozen=True)
class PromptCachePolicy:
    enabled: bool
    cache_key: str
    static_system: str
    dynamic_system: str
    auto_cache_conversation: bool = True
    anthropic_ttl: str = ANTHROPIC_PROMPT_CACHE_TTL
    openai_retention: str = OPENAI_PROMPT_CACHE_RETENTION

    @classmethod
    def from_structured_prompt(
        cls,
        structured: StructuredSystemPrompt,
        provider_type: str,
        *,
        static_token_estimate: int,
        auto_cache_conversation: bool = True,
    ) -> PromptCachePolicy:
        provider = (provider_type or "").strip().lower()
        static_text = structured.static_cacheable_text()
        dynamic_text = structured.dynamic_system_text()
        eligible = (
            PROMPT_CACHE_ENABLED
            and provider in ("openai", "anthropic")
            and bool(static_text.strip())
            and static_token_estimate >= PROMPT_CACHE_MIN_STATIC_TOKENS
        )
        return cls(
            enabled=eligible,
            cache_key=structured.cache_key(),
            static_system=static_text,
            dynamic_system=dynamic_text,
            auto_cache_conversation=auto_cache_conversation and eligible,
            anthropic_ttl=ANTHROPIC_PROMPT_CACHE_TTL,
            openai_retention=OPENAI_PROMPT_CACHE_RETENTION,
        )


def build_prompt_cache_policy(
    structured: StructuredSystemPrompt,
    provider_type: str,
    provider: Any = None,
    *,
    auto_cache_conversation: bool = True,
) -> PromptCachePolicy:
    estimate = structured.estimate_static_tokens(provider)
    return PromptCachePolicy.from_structured_prompt(
        structured,
        provider_type,
        static_token_estimate=estimate,
        auto_cache_conversation=auto_cache_conversation,
    )


def split_system_messages_for_provider(
    messages: List[Dict[str, Any]],
    policy: PromptCachePolicy,
) -> List[Dict[str, Any]]:
    """جایگزینی system تکی با static+dynamic برای prefix پایدار."""
    if not policy.enabled:
        return list(messages)

    rest: List[Dict[str, Any]] = []
    replaced = False
    for msg in messages:
        if not replaced and msg.get("role") == "system":
            replaced = True
            if policy.static_system:
                rest.append({"role": "system", "content": policy.static_system})
            if policy.dynamic_system:
                rest.append({"role": "system", "content": policy.dynamic_system})
            continue
        rest.append(dict(msg))
    return rest


def build_anthropic_system_blocks(policy: PromptCachePolicy) -> Optional[List[Dict[str, Any]]]:
    if not policy.enabled:
        return None
    blocks: List[Dict[str, Any]] = []
    if policy.static_system:
        blocks.append({"type": "text", "text": policy.static_system})
    if policy.dynamic_system:
        blocks.append({"type": "text", "text": policy.dynamic_system})
    if not blocks:
        return None
    # breakpoint روی آخرین block ثابت (static)
    if policy.static_system:
        blocks[0] = {
            **blocks[0],
            "cache_control": dict(ANTHROPIC_EPHEMERAL_CACHE),
        }
        if policy.anthropic_ttl and policy.anthropic_ttl != "5m":
            blocks[0]["cache_control"]["ttl"] = policy.anthropic_ttl
    return blocks


def anthropic_request_cache_control(
    policy: PromptCachePolicy,
    *,
    has_conversation: bool,
) -> Optional[Dict[str, Any]]:
    """Automatic caching برای رشد مکالمه در agent rounds."""
    if not policy.enabled or not policy.auto_cache_conversation:
        return None
    if not has_conversation:
        return None
    ctrl: Dict[str, Any] = dict(ANTHROPIC_EPHEMERAL_CACHE)
    if policy.anthropic_ttl and policy.anthropic_ttl != "5m":
        ctrl["ttl"] = policy.anthropic_ttl
    return ctrl


def merge_provider_extra(
    base: Optional[Dict[str, Any]],
    policy: Optional[PromptCachePolicy],
) -> Optional[Dict[str, Any]]:
    if not base and not (policy and policy.enabled):
        return base
    out = dict(base or {})
    if policy and policy.enabled:
        out["prompt_cache"] = {
            "enabled": True,
            "cache_key": policy.cache_key,
            "static_system": policy.static_system,
            "dynamic_system": policy.dynamic_system,
            "auto_cache_conversation": policy.auto_cache_conversation,
            "anthropic_ttl": policy.anthropic_ttl,
            "openai_retention": policy.openai_retention,
        }
    return out or None


def extract_prompt_cache_policy(
    provider_extra: Optional[Dict[str, Any]],
) -> Optional[PromptCachePolicy]:
    if not provider_extra:
        return None
    raw = provider_extra.get("prompt_cache")
    if not isinstance(raw, dict) or not raw.get("enabled"):
        return None
    return PromptCachePolicy(
        enabled=True,
        cache_key=str(raw.get("cache_key") or ""),
        static_system=str(raw.get("static_system") or ""),
        dynamic_system=str(raw.get("dynamic_system") or ""),
        auto_cache_conversation=bool(raw.get("auto_cache_conversation", True)),
        anthropic_ttl=str(raw.get("anthropic_ttl") or ANTHROPIC_PROMPT_CACHE_TTL),
        openai_retention=str(raw.get("openai_retention") or OPENAI_PROMPT_CACHE_RETENTION),
    )


def normalize_openai_usage(usage: Any) -> LLMUsageDetails:
    prompt_tokens = int(getattr(usage, "prompt_tokens", 0) or 0)
    completion_tokens = int(getattr(usage, "completion_tokens", 0) or 0)
    total_tokens = int(getattr(usage, "total_tokens", 0) or 0) or (
        prompt_tokens + completion_tokens
    )
    cached = 0
    details = getattr(usage, "prompt_tokens_details", None)
    if details is not None:
        cached = int(getattr(details, "cached_tokens", 0) or 0)
    return LLMUsageDetails(
        input_tokens=prompt_tokens,
        output_tokens=completion_tokens,
        total_tokens=total_tokens,
        cached_tokens=cached,
        cache_read_tokens=cached,
    )


def normalize_anthropic_usage(usage: Any) -> LLMUsageDetails:
    input_tokens = int(getattr(usage, "input_tokens", 0) or 0)
    output_tokens = int(getattr(usage, "output_tokens", 0) or 0)
    cache_creation = int(getattr(usage, "cache_creation_input_tokens", 0) or 0)
    cache_read = int(getattr(usage, "cache_read_input_tokens", 0) or 0)
    return LLMUsageDetails(
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        total_tokens=input_tokens + output_tokens,
        cache_creation_tokens=cache_creation,
        cache_read_tokens=cache_read,
        cached_tokens=cache_read,
    )


def usage_context_fields(details: LLMUsageDetails) -> Dict[str, Any]:
    if details.cache_read_tokens <= 0 and details.cache_creation_tokens <= 0:
        if details.cached_tokens <= 0:
            return {}
    return {
        "prompt_cache_read_tokens": details.cache_read_tokens,
        "prompt_cache_creation_tokens": details.cache_creation_tokens,
        "prompt_cache_hit_ratio": round(details.cache_hit_ratio(), 4),
    }
