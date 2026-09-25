"""Provider-neutral tool context transport.

Cached context is never an authorization decision.
Architecture does not depend on a single vendor cache feature.
"""
from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Any, Dict, Iterable, Optional, Sequence, Tuple

from app.services.ai.ai_prompt_cache import ANTHROPIC_EPHEMERAL_CACHE

STRATEGY_RESEND = "resend_required_schemas"
STRATEGY_PREFIX_CACHE = "stable_prefix_fingerprint"


@dataclass(frozen=True)
class ProviderContextPolicy:
    provider: str
    send_tools_every_request: bool
    supports_prompt_cache: bool
    supports_tool_prefix_cache: bool
    strategy: str
    fingerprint: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return {
            "provider": self.provider,
            "send_tools_every_request": self.send_tools_every_request,
            "supports_prompt_cache": self.supports_prompt_cache,
            "supports_tool_prefix_cache": self.supports_tool_prefix_cache,
            "strategy": self.strategy,
            "fingerprint": self.fingerprint,
            "authorization": "rechecked_every_request",
        }


def tool_context_fingerprint(
    names_and_versions: Sequence[Tuple[str, str]],
) -> str:
    parts = [f"{name}:{version}" for name, version in sorted(names_and_versions)]
    raw = "|".join(parts)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:24]


def fingerprint_from_state(state: Any) -> str:
    versions = getattr(state, "loaded_versions", None) or {}
    order = getattr(state, "order", None) or list(versions)
    pairs = [(name, str(versions.get(name) or "1")) for name in order if name]
    return tool_context_fingerprint(pairs)


def resolve_provider_context_policy(
    provider_type: Optional[str],
    *,
    fingerprint: str = "",
    openai_official: bool = False,
) -> ProviderContextPolicy:
    provider = (provider_type or "unknown").strip().lower()
    if provider == "anthropic":
        return ProviderContextPolicy(
            provider=provider,
            send_tools_every_request=True,
            supports_prompt_cache=True,
            supports_tool_prefix_cache=True,
            strategy=STRATEGY_PREFIX_CACHE,
            fingerprint=fingerprint,
        )
    if provider == "openai":
        return ProviderContextPolicy(
            provider=provider,
            send_tools_every_request=True,
            supports_prompt_cache=bool(openai_official),
            supports_tool_prefix_cache=False,
            strategy=STRATEGY_PREFIX_CACHE if openai_official else STRATEGY_RESEND,
            fingerprint=fingerprint,
        )
    return ProviderContextPolicy(
        provider=provider or "local",
        send_tools_every_request=True,
        supports_prompt_cache=False,
        supports_tool_prefix_cache=False,
        strategy=STRATEGY_RESEND,
        fingerprint=fingerprint,
    )


def attach_fingerprint_to_cache_key(cache_key: str, fingerprint: str) -> str:
    if not fingerprint:
        return cache_key
    base = (cache_key or "hx").rstrip(":")
    return f"{base}:tools:{fingerprint[:16]}"


def apply_anthropic_tool_cache(
    anthropic_tools: Optional[list],
    policy: Optional[ProviderContextPolicy],
) -> Optional[list]:
    """Mark last tool as cache breakpoint when the provider supports it.

    Tools are still sent every HTTP request. This only hints Anthropic to
    reuse the tools prefix when the fingerprint is unchanged.
    """
    if not anthropic_tools or not policy or not policy.supports_tool_prefix_cache:
        return anthropic_tools
    if not policy.fingerprint:
        return anthropic_tools
    cloned = [dict(item) for item in anthropic_tools]
    cloned[-1] = {**cloned[-1], "cache_control": dict(ANTHROPIC_EPHEMERAL_CACHE)}
    return cloned


def extract_provider_context_policy(
    provider_extra: Optional[Dict[str, Any]],
) -> Optional[ProviderContextPolicy]:
    if not provider_extra:
        return None
    raw = provider_extra.get("tool_context")
    if not isinstance(raw, dict):
        return None
    return ProviderContextPolicy(
        provider=str(raw.get("provider") or ""),
        send_tools_every_request=bool(raw.get("send_tools_every_request", True)),
        supports_prompt_cache=bool(raw.get("supports_prompt_cache", False)),
        supports_tool_prefix_cache=bool(raw.get("supports_tool_prefix_cache", False)),
        strategy=str(raw.get("strategy") or STRATEGY_RESEND),
        fingerprint=str(raw.get("fingerprint") or ""),
    )
