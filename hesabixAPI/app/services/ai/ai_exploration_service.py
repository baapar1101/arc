"""
Exploration mode — بررسی زنده، جمع‌بندی شواهد و یافته‌های کلیدی.

- ObservationStore: حافظهٔ ساخت‌یافته per-request
- Explored bundle: ادغام چند tool در یک کارت UX
- Thought: یافته‌های مهم (rule-based + اختیاری LLM)
- PII masking برای نمایش کاربر
"""
from __future__ import annotations

import json
import logging
import re
import uuid
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

from app.services.ai.ai_tool_intent import estimate_query_complexity
from app.services.ai.ai_tool_keys import tool_label_fa
from app.services.ai.ai_trace import summarize_tool_result

logger = logging.getLogger(__name__)

EXPLORATION_MODE_EXPLORE = "explore"
EXPLORATION_MODE_AUTO = "auto"
EXPLORATION_MODE_OFF = "off"

# کلید تزریق Thought به context مدل (مرحله بعد)
AGENT_THOUGHT_MESSAGE_TAG = "[agent_thought]"

_SENSITIVE_KEYS = frozenset({
    "api_key",
    "private_key",
    "password",
    "secret",
    "token",
    "certificate",
    "csr",
    "jwt",
})

_ECONOMIC_CODE_RE = re.compile(r"\b\d{10,14}\b")


@dataclass
class ToolObservation:
    tool_name: str
    arguments: Dict[str, Any]
    result: Any
    success: bool
    elapsed_ms: Optional[int] = None
    citations: Optional[List[str]] = None


@dataclass
class ExplorationBundle:
    bundle_id: str
    iteration: int
    title: str
    explore_targets: List[str]
    observations: List[ToolObservation] = field(default_factory=list)

    @property
    def tool_count(self) -> int:
        return len(self.observations)

    @property
    def has_errors(self) -> bool:
        return any(not o.success for o in self.observations)


@dataclass
class ThoughtRecord:
    thought_id: str
    bundle_id: str
    iteration: int
    body_markdown: str
    hypothesis: Optional[str] = None
    confidence: Optional[str] = None  # low | medium | high
    open_questions: List[str] = field(default_factory=list)


class ObservationStore:
    """حافظهٔ کاوش در یک پاسخ assistant."""

    def __init__(self) -> None:
        self.bundles: List[ExplorationBundle] = []
        self.thoughts: List[ThoughtRecord] = []
        self.open_questions: List[str] = []

    def add_bundle(self, bundle: ExplorationBundle) -> None:
        self.bundles.append(bundle)

    def add_thought(self, thought: ThoughtRecord) -> None:
        self.thoughts.append(thought)
        self.open_questions.extend(thought.open_questions)

    def latest_thought_markdown(self) -> Optional[str]:
        if not self.thoughts:
            return None
        return self.thoughts[-1].body_markdown

    def context_for_llm(self) -> Optional[str]:
        """متن فشرده برای تزریق به حلقهٔ agent."""
        if not self.thoughts:
            return None
        parts: List[str] = []
        for t in self.thoughts[-3:]:
            parts.append(t.body_markdown)
        if self.open_questions:
            parts.append(
                "**سوالات باز:**\n"
                + "\n".join(f"- {q}" for q in self.open_questions[-5:])
            )
        return f"{AGENT_THOUGHT_MESSAGE_TAG}\n\n" + "\n\n---\n\n".join(parts)


def resolve_exploration_enabled(
    exploration_mode: Optional[str],
    user_query: Optional[str],
    history_messages: Optional[List[dict]] = None,
) -> bool:
    mode = (exploration_mode or EXPLORATION_MODE_AUTO).strip().lower()
    if mode == EXPLORATION_MODE_OFF:
        return False
    if mode == EXPLORATION_MODE_EXPLORE:
        return True
    # auto
    complexity = estimate_query_complexity(user_query, history_messages)
    return complexity in ("medium", "complex")


def new_bundle_id(iteration: int) -> str:
    return f"bundle_{iteration}_{uuid.uuid4().hex[:8]}"


def explore_target_for_call(function_name: str, arguments: Any) -> str:
    """برچسب کوتاه برای خط Exploring."""
    label = tool_label_fa(function_name)
    args = arguments if isinstance(arguments, dict) else {}
    hints: List[str] = []
    for key in ("business_id", "invoice_id", "person_id", "product_id", "id"):
        if key in args and args[key] is not None:
            hints.append(f"{key}={args[key]}")
    if hints:
        return f"{label} ({', '.join(hints[:2])})"
    q = args.get("query") or args.get("search") or args.get("code")
    if isinstance(q, str) and q.strip():
        return f"{label}: {q.strip()[:40]}"
    return label


def bundle_title_from_calls(function_calls: List[Dict[str, Any]]) -> str:
    if len(function_calls) == 1:
        return explore_target_for_call(
            function_calls[0].get("name", "unknown"),
            function_calls[0].get("arguments", {}),
        )
    labels = [
        tool_label_fa(c.get("name", "unknown")) for c in function_calls[:4]
    ]
    if len(function_calls) > 4:
        return f"{', '.join(labels)} +{len(function_calls) - 4}"
    return " · ".join(labels)


def build_explored_body_markdown(
    bundle: ExplorationBundle,
    *,
    mask_pii: bool = True,
) -> str:
    """جدول/خلاصهٔ Explored برای UI."""
    lines: List[str] = []
    for obs in bundle.observations:
        label = tool_label_fa(obs.tool_name)
        status = "✓" if obs.success else "✗"
        summary = summarize_tool_result(obs.tool_name, obs.result)
        if mask_pii:
            summary = mask_sensitive_text(summary)
        lines.append(f"#### {status} {label}")
        if summary.strip():
            lines.append(summary.strip())
        if obs.citations:
            refs = ", ".join(obs.citations[:5])
            if len(obs.citations) > 5:
                refs += f" (+{len(obs.citations) - 5})"
            lines.append(f"*منابع:* {refs}")
        lines.append("")
    return "\n".join(lines).strip()


def _extract_claims_from_result(tool_name: str, result: Any) -> List[str]:
    """استخراج claimهای ساخت‌یافته از نتیجه tool."""
    claims: List[str] = []
    if not isinstance(result, dict):
        return claims
    if result.get("error"):
        msg = result.get("message") or result.get("error")
        claims.append(f"خطا در {tool_label_fa(tool_name)}: {msg}")
        return claims
    for key in ("message", "summary", "description", "status"):
        val = result.get(key)
        if isinstance(val, str) and val.strip():
            claims.append(val.strip()[:400])
            break
    for key in ("items", "data", "results", "invoices", "products"):
        items = result.get(key)
        if isinstance(items, list) and items:
            total = (
                (result.get("pagination") or {}).get("total")
                if isinstance(result.get("pagination"), dict)
                else len(items)
            )
            claims.append(f"{tool_label_fa(tool_name)}: **{total}** مورد")
            break
    # فیلدهای حساس / مالیاتی
    for key in (
        "tax_memory_id",
        "fiscal_id",
        "economic_code",
        "taxpayer_id",
        "sandbox",
        "certificate",
        "tracking_code",
        "error_code",
    ):
        if key in result and result[key] is not None:
            val = result[key]
            if isinstance(val, str) and len(val) > 80:
                val = f"{val[:40]}… ({len(val)} chars)"
            claims.append(f"**{key}**: `{val}`")
    return claims[:8]


def build_thought_markdown_rule_based(
    bundle: ExplorationBundle,
    user_query: Optional[str],
) -> Tuple[str, Optional[str], str, List[str]]:
    """
    Thought بدون LLM — سریع و پایدار.
    Returns: (body_markdown, hypothesis, confidence, open_questions)
    """
    findings: List[str] = []
    open_questions: List[str] = []
    errors = 0
    for obs in bundle.observations:
        if not obs.success:
            errors += 1
        findings.extend(_extract_claims_from_result(obs.tool_name, obs.result))

    if not findings:
        for obs in bundle.observations:
            snippet = summarize_tool_result(obs.tool_name, obs.result)
            if snippet.strip():
                findings.append(
                    f"**{tool_label_fa(obs.tool_name)}:** {snippet.strip()[:300]}"
                )

    findings = findings[:7]
    body_lines = ["### Important findings", ""]
    for i, f in enumerate(findings, 1):
        body_lines.append(f"{i}. {mask_sensitive_text(f)}")

    hypothesis: Optional[str] = None
    confidence = "medium"
    if errors == len(bundle.observations) and bundle.tool_count > 0:
        hypothesis = "اجرای ابزارها با خطا مواجه شد؛ داده کافی برای نتیجه‌گیری نیست."
        confidence = "low"
        open_questions.append("آیا پارامترهای جستجو (شناسه کسب‌وکار، فاکتور و …) درست است؟")
    elif errors > 0:
        hypothesis = "بخشی از داده‌ها در دسترس نبود؛ پاسخ بر اساس شواهد موجود است."
        confidence = "medium"
    elif len(findings) >= 3:
        hypothesis = "شواهد کافی جمع شد؛ می‌توان پاسخ نهایی یا کاوش تکمیلی ارائه داد."
        confidence = "high"
    elif findings:
        hypothesis = "یافته‌های اولیه ثبت شد؛ در صورت نیاز کاوش تکمیلی پیشنهاد می‌شود."
        confidence = "medium"
    else:
        hypothesis = "نتیجهٔ ابزارها خالی یا غیرقابل تفسیر بود."
        confidence = "low"
        open_questions.append("سوال را دقیق‌تر یا با شناسه مشخص تکرار کنید.")

    if hypothesis:
        body_lines.extend(["", f"**فرضیه:** {hypothesis}"])

    body = "\n".join(body_lines)
    return body, hypothesis, confidence, open_questions


def should_continue_exploring(
    store: ObservationStore,
    iteration: int,
    max_iterations: int,
) -> bool:
    """آیا پس از Thought هنوز کاوش لازم است؟"""
    if iteration >= max_iterations:
        return False
    if not store.thoughts:
        return True
    last = store.thoughts[-1]
    if last.confidence == "high" and not last.open_questions:
        return False
    if last.confidence == "low" and iteration < max_iterations - 1:
        return True
    return bool(last.open_questions) and iteration < max_iterations


async def synthesize_thought_with_llm(
    provider: Any,
    model: str,
    max_tokens: int,
    temperature: float,
    bundle: ExplorationBundle,
    user_query: Optional[str],
    explored_markdown: str,
) -> Optional[str]:
    """Thought غنی با LLM (اختیاری، فقط explore صریح)."""
    import asyncio

    system = (
        "You are an analyst for an Iranian accounting ERP (Hesabix). "
        "Given tool results, write concise Important findings in Persian. "
        "Use markdown: ### Important findings, numbered list, then **فرضیه:** one sentence. "
        "Do not invent data. Mask secrets (show only last 4 chars of keys). Max 400 words."
    )
    user_content = (
        f"User question: {user_query or ''}\n\n"
        f"Tools in this bundle: {bundle.title}\n\n"
        f"Results:\n{explored_markdown[:6000]}"
    )
    messages = [
        {"role": "system", "content": system},
        {"role": "user", "content": user_content},
    ]

    def _run() -> Dict[str, Any]:
        return provider.chat_completion(
            messages=messages,
            model=model,
            max_tokens=min(900, max_tokens),
            temperature=min(0.4, float(temperature)),
            tools=None,
        )

    try:
        loop = asyncio.get_event_loop()
        resp = await loop.run_in_executor(None, _run)
        choices = resp.get("choices") or []
        if not choices:
            return None
        msg = choices[0].get("message") or {}
        content = msg.get("content")
        if isinstance(content, str) and content.strip():
            return content.strip()
    except Exception as exc:
        logger.warning("LLM thought synthesis failed: %s", exc)
    return None


def mask_sensitive_text(text: str, *, admin_view: bool = False) -> str:
    """ماسک PII/رمز برای نمایش کاربر عادی."""
    if admin_view or not text:
        return text
    out = text
    for key in _SENSITIVE_KEYS:
        pattern = re.compile(
            rf"(\*\*{key}\*\*:\s*`)([^`]+)(`)",
            re.IGNORECASE,
        )
        out = pattern.sub(
            lambda m: f"{m.group(1)}{_mask_value(m.group(2), key)}{m.group(3)}",
            out,
        )
    # economic codes in plain text
    def _mask_code(match: re.Match) -> str:
        s = match.group(0)
        if len(s) <= 6:
            return s
        return s[:4] + "…" + s[-2:]

    out = _ECONOMIC_CODE_RE.sub(_mask_code, out)
    if "plain text" in out.lower() or "plain_text" in out.lower():
        out = re.sub(
            r"(plain\s*text[^.\n]*)",
            "ذخیرهٔ ناامن (جزئیات فقط برای مدیر)",
            out,
            flags=re.IGNORECASE,
        )
    return out


def _mask_value(value: str, key: str) -> str:
    key_l = key.lower()
    if "key" in key_l or "secret" in key_l or "token" in key_l:
        if len(value) <= 8:
            return "****"
        return f"…{value[-4:]} ({len(value)} chars)"
    if "certificate" in key_l or "csr" in key_l:
        if len(value) == 0 or value in ("0", "None", "null"):
            return "خالی"
        return f"[{len(value)} chars]"
    return value[:6] + "…" if len(value) > 12 else value


def extract_entity_refs_from_calls(
    function_calls: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    """ارجاع entity برای لینک در UI."""
    refs: List[Dict[str, Any]] = []
    seen: set = set()
    for call in function_calls:
        args = call.get("arguments") or {}
        if not isinstance(args, dict):
            continue
        mapping = [
            ("invoice_id", "invoice"),
            ("person_id", "person"),
            ("product_id", "product"),
            ("business_id", "business"),
            ("lead_id", "lead"),
            ("deal_id", "deal"),
        ]
        for field, entity_type in mapping:
            val = args.get(field)
            if val is not None:
                key = f"{entity_type}:{val}"
                if key not in seen:
                    seen.add(key)
                    refs.append({"type": entity_type, "id": val})
    return refs[:8]
