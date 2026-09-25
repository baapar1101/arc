"""
ساختار لایه‌ای system prompt برای Prompt Caching در سطح Provider.

طراحی:
  - static_core: بلوک‌های نقش از DB (فقط با ویرایش admin عوض می‌شود)
  - business_anchor: شناسه کسب‌وکار + تقویم (پایدار per business)
  - semi_static: حافظه + بینش + کانکتور (پایدار تا TTL بینش؛ بدون datetime)
  - execution/plan + runtime: متغیر per request (datetime، دانش، مهارت، پیوست، todo)
"""
from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Any, List, Optional, Sequence, Union

from app.services.ai.ai_message_budget import trim_system_prompt, trim_system_prompt_sections
from app.services.ai.ai_constants import MAX_SYSTEM_PROMPT_CHARS


SEMI_STATIC_PART_KEYS: tuple[str, ...] = ("memory", "insights", "connectors")
DYNAMIC_RUNTIME_PART_KEYS: tuple[str, ...] = (
    "datetime",
    "knowledge",
    "skills",
    "attachments",
    "todos",
)


def _estimate_tokens(text: str, provider: Any = None) -> int:
    if not text:
        return 0
    if provider is not None and hasattr(provider, "estimate_tokens"):
        return int(provider.estimate_tokens(text))
    return max(1, len(text) // 4)


@dataclass(frozen=True)
class StructuredSystemPrompt:
    static_core: str
    business_anchor: str
    execution_block: str
    plan_block: str
    runtime_sections: tuple[str, ...]
    role: str
    business_id: Optional[int]
    semi_static_sections: tuple[str, ...] = ()
    insights_section: str = ""

    def full_text(self) -> str:
        """متن نهایی system prompt (همان خروجی legacy)."""
        return (
            self.static_cacheable_text()
            + self.semi_static_text()
            + self.dynamic_system_text()
        )

    def static_cacheable_text(self) -> str:
        """پrefix پایدار برای Provider cache breakpoint."""
        combined = (self.static_core or "") + (self.business_anchor or "")
        return trim_system_prompt(combined)

    def semi_static_text(self) -> str:
        """حافظه + بینش + کانکتور — لایهٔ cache نیمه‌پایدار (PRM-04)."""
        sections = [s for s in self.semi_static_sections if s and str(s).strip()]
        if not sections:
            return ""
        used = len(self.static_cacheable_text())
        budget = max(256, MAX_SYSTEM_PROMPT_CHARS - used)
        return trim_system_prompt_sections("", sections, max_chars=budget)

    def dynamic_system_text(self) -> str:
        """بخش متغیر system prompt (بعد از breakpointهای static و semi_static)."""
        used = len(self.static_cacheable_text()) + len(self.semi_static_text())
        dynamic_budget = max(256, MAX_SYSTEM_PROMPT_CHARS - used)
        return trim_system_prompt_sections(
            (self.execution_block or "") + (self.plan_block or ""),
            list(self.runtime_sections),
            max_chars=dynamic_budget,
        )

    def cache_key(self) -> str:
        """کلید مسیریابی OpenAI prompt_cache_key.

        hash لایهٔ نیمه‌پایدار هم هست تا وقتی KPI/حافظه عوض شود prefix جدا شود؛
        execution و datetime در key نیستند.
        """
        static_hash = hashlib.sha256(
            self.static_cacheable_text().encode("utf-8")
        ).hexdigest()[:16]
        semi_hash = hashlib.sha256(
            self.semi_static_text().encode("utf-8")
        ).hexdigest()[:12]
        biz = self.business_id if self.business_id is not None else 0
        return f"hx:v1:{self.role}:{biz}:{static_hash}:{semi_hash}"

    def estimate_static_tokens(self, provider: Any = None) -> int:
        return _estimate_tokens(self.static_cacheable_text(), provider)

    def estimate_section_tokens(self, provider: Any = None) -> dict[str, int]:
        return {
            "static_tokens": self.estimate_static_tokens(provider),
            "semi_static_tokens": _estimate_tokens(self.semi_static_text(), provider),
            "insights_tokens": _estimate_tokens(self.insights_section or "", provider),
            "runtime_tokens": _estimate_tokens(self.dynamic_system_text(), provider),
        }

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
    semi_static_sections: Optional[Sequence[str]] = None,
    insights_section: str = "",
    role: str,
    business_id: Optional[int] = None,
) -> StructuredSystemPrompt:
    sections = tuple(s for s in (runtime_sections or ()) if s and str(s).strip())
    semi = tuple(s for s in (semi_static_sections or ()) if s and str(s).strip())
    return StructuredSystemPrompt(
        static_core=static_core or "",
        business_anchor=business_anchor or "",
        execution_block=execution_block or "",
        plan_block=plan_block or "",
        runtime_sections=sections,
        role=role,
        business_id=business_id,
        semi_static_sections=semi,
        insights_section=insights_section or "",
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
    """ترتیب اولویت runtime مطابق trim_system_prompt_sections (legacy، همه لایه‌ها)."""
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


def split_runtime_prompt_parts(
    parts: dict[str, str],
) -> tuple[List[str], List[str], str]:
    """جدا کردن لایهٔ نیمه‌پایدار از runtime متغیر (PRM-04).

    برمی‌گرداند: (semi_static_sections, dynamic_runtime_sections, insights_text)
    """
    semi = [parts.get(key, "") or "" for key in SEMI_STATIC_PART_KEYS]
    dynamic = [parts.get(key, "") or "" for key in DYNAMIC_RUNTIME_PART_KEYS]
    return semi, dynamic, parts.get("insights", "") or ""
