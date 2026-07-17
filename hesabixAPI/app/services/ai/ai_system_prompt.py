"""
ساختار لایه‌ای system prompt برای Prompt Caching در سطح Provider.

طراحی:
  - static_core: بلوک‌های نقش از DB (فقط با ویرایش admin عوض می‌شود)
  - business_anchor: شناسه کسب‌وکار + تقویم (پایدار per business)
  - execution/plan + runtime: متغیر per request/session
"""
from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Any, List, Optional, Sequence, Union

from app.services.ai.ai_message_budget import trim_system_prompt, trim_system_prompt_sections
from app.services.ai.ai_constants import MAX_SYSTEM_PROMPT_CHARS


@dataclass(frozen=True)
class StructuredSystemPrompt:
    static_core: str
    business_anchor: str
    execution_block: str
    plan_block: str
    runtime_sections: tuple[str, ...]
    role: str
    business_id: Optional[int]

    def full_text(self) -> str:
        """متن نهایی system prompt (همان خروجی legacy)."""
        return trim_system_prompt_sections(
            self.static_core
            + self.business_anchor
            + self.execution_block
            + self.plan_block,
            list(self.runtime_sections),
        )

    def static_cacheable_text(self) -> str:
        """پrefix پایدار برای Provider cache breakpoint."""
        combined = (self.static_core or "") + (self.business_anchor or "")
        return trim_system_prompt(combined)

    def dynamic_system_text(self) -> str:
        """بخش متغیر system prompt (بعد از breakpoint)."""
        static_len = len(self.static_cacheable_text())
        dynamic_budget = max(256, MAX_SYSTEM_PROMPT_CHARS - static_len)
        return trim_system_prompt_sections(
            (self.execution_block or "") + (self.plan_block or ""),
            list(self.runtime_sections),
            max_chars=dynamic_budget,
        )

    def cache_key(self) -> str:
        """کلید مسیریابی OpenAI prompt_cache_key."""
        static_hash = hashlib.sha256(
            self.static_cacheable_text().encode("utf-8")
        ).hexdigest()[:16]
        biz = self.business_id if self.business_id is not None else 0
        return f"hx:v1:{self.role}:{biz}:{static_hash}"

    def estimate_static_tokens(self, provider: Any = None) -> int:
        text = self.static_cacheable_text()
        if provider is not None and hasattr(provider, "estimate_tokens"):
            return int(provider.estimate_tokens(text))
        return max(1, len(text) // 4)

    @classmethod
    def from_legacy_text(
        cls,
        text: str,
        *,
        role: str = "user",
        business_id: Optional[int] = None,
    ) -> StructuredSystemPrompt:
        """سازگاری با prebuilt string (streaming legacy)."""
        return cls(
            static_core=text or "",
            business_anchor="",
            execution_block="",
            plan_block="",
            runtime_sections=(),
            role=role,
            business_id=business_id,
        )


def compose_structured_system_prompt(
    *,
    static_core: str,
    business_anchor: str = "",
    execution_block: str = "",
    plan_block: str = "",
    runtime_sections: Optional[Sequence[str]] = None,
    role: str,
    business_id: Optional[int] = None,
) -> StructuredSystemPrompt:
    sections = tuple(s for s in (runtime_sections or ()) if s and str(s).strip())
    return StructuredSystemPrompt(
        static_core=static_core or "",
        business_anchor=business_anchor or "",
        execution_block=execution_block or "",
        plan_block=plan_block or "",
        runtime_sections=sections,
        role=role,
        business_id=business_id,
    )


def coerce_structured_system_prompt(
    prompt: Union[str, StructuredSystemPrompt, None],
    *,
    role: str = "user",
    business_id: Optional[int] = None,
) -> StructuredSystemPrompt:
    if isinstance(prompt, StructuredSystemPrompt):
        return prompt
    if prompt is None:
        return StructuredSystemPrompt.from_legacy_text("", role=role, business_id=business_id)
    return StructuredSystemPrompt.from_legacy_text(
        str(prompt), role=role, business_id=business_id
    )


def runtime_sections_from_parts(parts: dict[str, str]) -> List[str]:
    """ترتیب اولویت runtime مطابق trim_system_prompt_sections."""
    return [
        parts.get("datetime", ""),
        parts.get("memory", ""),
        parts.get("insights", ""),
        parts.get("knowledge", ""),
        parts.get("skills", ""),
        parts.get("connectors", ""),
        parts.get("attachments", ""),
        parts.get("todos", ""),
    ]
