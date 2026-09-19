"""
Agent trace — زنجیرهٔ مراحل قابل نمایش برای کاربر.
"""
from __future__ import annotations

import json
import re
import uuid
from typing import Any, Dict, List, Optional

from app.services.ai.ai_tool_keys import tool_label_fa, tool_l10n_key

TRACE_AGENT_KEY = "_agent_trace"
TRACE_REASONING_KEY = "_reasoning_trace"

# لایهٔ نمایش / ذخیره
TRACE_LAYER_REASONING = "reasoning"
TRACE_LAYER_ANSWER = "answer"
TRACE_LAYER_SYSTEM = "system"

TRACE_VISIBILITY_USER = "user"
TRACE_VISIBILITY_INTERNAL = "internal"

# نگاشت step آماده‌سازی context به کلید l10n
CONTEXT_STEP_TITLE_KEYS: Dict[str, str] = {
    "loading_prompt": "aiStatusLoadingPrompt",
    "loading_insights": "aiStatusLoadingInsights",
    "loading_memory": "aiStatusLoadingMemory",
    "loading_attachments": "aiStatusLoadingAttachments",
    "loading_knowledge": "aiStatusLoadingKnowledge",
    "loading_connectors": "aiStatusLoadingConnectors",
    "loading_session_todos": "aiStatusLoadingSessionPlan",
}

TraceKind = str  # context | explore | explored | thought | plan | narrative | tool | observation | plan_next | answer | system
TraceState = str  # active | done | error
TraceLayer = str  # reasoning | answer | system


def new_trace_id() -> str:
    return uuid.uuid4().hex[:12]


def layer_for_kind(kind: TraceKind) -> TraceLayer:
    if kind == "answer":
        return TRACE_LAYER_ANSWER
    if kind == "system":
        return TRACE_LAYER_SYSTEM
    return TRACE_LAYER_REASONING


def trace_step(
    step_id: str,
    kind: TraceKind,
    state: TraceState = "done",
    *,
    title_key: Optional[str] = None,
    title_params: Optional[Dict[str, Any]] = None,
    body_markdown: Optional[str] = None,
    tool: Optional[str] = None,
    tool_key: Optional[str] = None,
    iteration: Optional[int] = None,
    elapsed_ms: Optional[int] = None,
    result_count: Optional[int] = None,
    citations: Optional[List[str]] = None,
    bundle_id: Optional[str] = None,
    explore_target: Optional[str] = None,
    entity_refs: Optional[List[Dict[str, Any]]] = None,
    findings_count: Optional[int] = None,
    hypothesis: Optional[str] = None,
    confidence: Optional[str] = None,
    layer: Optional[TraceLayer] = None,
    trace_id: Optional[str] = None,
    visibility: str = TRACE_VISIBILITY_USER,
    retry_attempt: Optional[int] = None,
    subagent_id: Optional[str] = None,
    parent_step_id: Optional[str] = None,
) -> Dict[str, Any]:
    resolved_layer = layer or layer_for_kind(kind)
    payload: Dict[str, Any] = {
        "event": "trace_step",
        "trace_id": trace_id or new_trace_id(),
        "step_id": step_id,
        "kind": kind,
        "state": state,
        "layer": resolved_layer,
        "visibility": visibility,
    }
    if retry_attempt is not None:
        payload["retry_attempt"] = retry_attempt
    if title_key:
        payload["title_key"] = title_key
    if title_params:
        payload["title_params"] = title_params
    if body_markdown:
        payload["body_markdown"] = body_markdown
    if tool:
        payload["tool"] = tool
    if tool_key:
        payload["tool_key"] = tool_key
    if iteration is not None:
        payload["iteration"] = iteration
    if elapsed_ms is not None:
        payload["elapsed_ms"] = elapsed_ms
    if result_count is not None:
        payload["result_count"] = result_count
    if citations:
        payload["citations"] = citations
    if bundle_id:
        payload["bundle_id"] = bundle_id
    if explore_target:
        payload["explore_target"] = explore_target
    if entity_refs:
        payload["entity_refs"] = entity_refs
    if findings_count is not None:
        payload["findings_count"] = findings_count
    if hypothesis:
        payload["hypothesis"] = hypothesis
    if confidence:
        payload["confidence"] = confidence
    if subagent_id:
        payload["subagent_id"] = subagent_id
    if parent_step_id:
        payload["parent_step_id"] = parent_step_id
    return payload


def trace_record_from_event(event: Dict[str, Any]) -> Dict[str, Any]:
    """نسخهٔ ذخیره‌شده در DB (بدون event)."""
    return {k: v for k, v in event.items() if k != "event"}


def context_trace(step_key: str, state: TraceState) -> Dict[str, Any]:
    """گام ثابت context با step_id پایدار برای به‌روزرسانی active → done."""
    return trace_step(
        f"ctx_{step_key}",
        "context",
        state,
        title_key=CONTEXT_STEP_TITLE_KEYS.get(step_key, "aiStatusPreparingContext"),
    )


def format_tool_arguments(arguments: Any) -> str:
    if not arguments:
        return ""
    if isinstance(arguments, str):
        try:
            arguments = json.loads(arguments)
        except json.JSONDecodeError:
            return arguments[:500]
    if not isinstance(arguments, dict):
        return str(arguments)[:500]
    parts: List[str] = []
    for key, value in arguments.items():
        if value is None or value == "":
            continue
        parts.append(f"- **{key}**: {value}")
    return "\n".join(parts) if parts else ""


def format_planned_tools(function_calls: List[Dict[str, Any]]) -> str:
    lines: List[str] = []
    for call in function_calls:
        name = call.get("name", "unknown")
        label = tool_label_fa(name)
        args_md = format_tool_arguments(call.get("arguments", {}))
        lines.append(f"### {label}")
        if args_md:
            lines.append(args_md)
        else:
            lines.append("- بدون پارامتر اضافی")
    return "\n\n".join(lines)


def summarize_tool_result_for_llm(function_name: str, result: Any) -> str:
    """خلاصهٔ فشرده برای قرار دادن در پیام role=tool (کاهش توکن)."""
    from app.services.ai.ai_tool_result import compact_tool_result_for_llm

    return compact_tool_result_for_llm(function_name, result)


def summarize_tool_result(function_name: str, result: Any) -> str:
    """خلاصهٔ خوانا از نتیجهٔ tool برای نمایش در trace."""
    if result is None:
        return "نتیجه‌ای برنگشت."

    if isinstance(result, dict):
        if result.get("error") == "APPROVAL_REQUIRED":
            msg = result.get("message") or "نیاز به تأیید کاربر"
            return f"⏸ {msg}"
        if "error" in result:
            return f"خطا: {result.get('error')}"

        # workflow / اتوماسیون
        if function_name in (
            "create_workflow",
            "update_workflow",
            "get_workflow",
            "test_workflow",
        ):
            parts: List[str] = []
            if result.get("name"):
                parts.append(f"**{result['name']}**")
            wid = result.get("id") or result.get("workflow_id")
            if wid is not None:
                parts.append(f"شناسه: `{wid}`")
            if result.get("status"):
                parts.append(f"وضعیت: {result['status']}")
            if result.get("editor_path"):
                parts.append(f"ادیتور: `{result['editor_path']}`")
            if result.get("sandbox_used"):
                parts.append("_(تست روی پیش‌نمایش sandbox)_")
            if result.get("summary") and isinstance(result["summary"], dict):
                s = result["summary"]
                parts.append(
                    f"نتیجه اجرا: {s.get('status', '—')} — خطاهای نود: {s.get('failed_node_count', 0)}"
                )
            if parts:
                return "\n".join(parts)

        # پیام مستقیم
        for key in ("message", "summary", "description", "note"):
            if isinstance(result.get(key), str) and result[key].strip():
                return result[key].strip()[:1200]

        # لیست‌ها
        for key in ("items", "data", "results", "invoices", "products", "persons", "leads", "deals"):
            items = result.get(key)
            if isinstance(items, list):
                count = len(items)
                preview = _preview_list_items(items, limit=3)
                return f"**{count}** مورد یافت شد.\n\n{preview}"

        # اعداد کلیدی
        numeric_lines = _extract_numeric_highlights(result)
        if numeric_lines:
            return "\n".join(numeric_lines[:12])

        # fallback کوتاه
        text = json.dumps(result, ensure_ascii=False, indent=0)
        if len(text) > 900:
            return text[:900] + "…"
        return f"```json\n{text}\n```"

    if isinstance(result, list):
        preview = _preview_list_items(result, limit=3)
        return f"**{len(result)}** مورد.\n\n{preview}"

    text = str(result)
    return text[:900] + ("…" if len(text) > 900 else "")


def _preview_list_items(items: List[Any], limit: int = 3) -> str:
    lines: List[str] = []
    for item in items[:limit]:
        if isinstance(item, dict):
            label = (
                item.get("name")
                or item.get("title")
                or item.get("code")
                or item.get("number")
                or item.get("id")
            )
            extra = item.get("total") or item.get("amount") or item.get("balance")
            if label is not None and extra is not None:
                lines.append(f"- {label}: {extra}")
            elif label is not None:
                lines.append(f"- {label}")
            else:
                lines.append(f"- {_short_json(item)}")
        else:
            lines.append(f"- {item}")
    if len(items) > limit:
        lines.append(f"- … و **{len(items) - limit}** مورد دیگر")
    return "\n".join(lines) if lines else ""


def _extract_numeric_highlights(data: Dict[str, Any], prefix: str = "") -> List[str]:
    lines: List[str] = []
    for key, value in data.items():
        if key.startswith("_"):
            continue
        label = f"{prefix}{key}" if not prefix else f"{prefix}.{key}"
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            lines.append(f"- **{label}**: {value:,}")
        elif isinstance(value, dict) and len(lines) < 8:
            lines.extend(_extract_numeric_highlights(value, label)[:4])
    return lines


def _short_json(obj: Dict[str, Any]) -> str:
    text = json.dumps(obj, ensure_ascii=False)
    return text[:120] + ("…" if len(text) > 120 else "")


def extract_result_count(result: Any) -> Optional[int]:
    """تعداد رکوردهای برگشتی از نتیجه tool را استخراج می‌کند."""
    if not isinstance(result, dict):
        if isinstance(result, list):
            return len(result)
        return None

    # pagination.total
    pagination = result.get("pagination")
    if isinstance(pagination, dict):
        total = pagination.get("total")
        if isinstance(total, int):
            return total

    # لیست‌های رایج
    for key in ("items", "data", "results", "invoices", "products", "persons",
                "leads", "deals", "documents", "checks"):
        items = result.get(key)
        if isinstance(items, list):
            return len(items)

    return None


def extract_citations_from_result(result: Any) -> List[str]:
    """استخراج منابع/citation از نتیجه tool برای trace UI."""
    from app.services.ai.ai_citation_service import format_citation_lines
    from app.services.ai.ai_tool_result import (
        extract_record_citations,
        extract_record_list,
        unwrap_registry_result,
    )

    payload = unwrap_registry_result(result)
    refs: List[Dict[str, Any]] = []
    if isinstance(payload, dict) and isinstance(payload.get("citations"), list):
        refs = [dict(x) for x in payload["citations"] if isinstance(x, dict)]
    if not refs:
        records, _ = extract_record_list(payload)
        refs = extract_record_citations(records, limit=5)
    lines = format_citation_lines(refs[:5])
    return [line.lstrip("- ").strip() for line in lines if line.strip()]


def split_trace_layers(
    trace_steps: List[Dict[str, Any]],
) -> tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """جداسازی trace استدلال از trace کامل برای ذخیره."""
    reasoning: List[Dict[str, Any]] = []
    for step in trace_steps:
        layer = step.get("layer") or layer_for_kind(step.get("kind", ""))
        if layer == TRACE_LAYER_ANSWER:
            continue
        reasoning.append(step)
    return trace_steps, reasoning


def finalize_trace_steps_for_persist(
    trace_steps: Optional[List[Dict[str, Any]]],
) -> List[Dict[str, Any]]:
    """بستن stepهای active و پاک‌سازی body_markdown قبل از ذخیره در DB."""
    if not trace_steps:
        return []
    from app.services.ai.ai_content_sanitize import sanitize_assistant_content

    finalized: List[Dict[str, Any]] = []
    for step in trace_steps:
        record = dict(step)
        if record.get("state") == "active":
            record["state"] = "done"
        body = record.get("body_markdown")
        if isinstance(body, str) and body:
            record["body_markdown"] = sanitize_assistant_content(body)
        finalized.append(record)
    return finalized


def merge_trace_into_function_results(
    function_results: Optional[Dict[str, Any]],
    trace_steps: List[Dict[str, Any]],
) -> Dict[str, Any]:
    merged = dict(function_results or {})
    finalized = finalize_trace_steps_for_persist(trace_steps)
    if finalized:
        merged[TRACE_AGENT_KEY] = finalized
        _, reasoning = split_trace_layers(finalized)
        if reasoning:
            merged[TRACE_REASONING_KEY] = reasoning
    return merged


def extract_trace_from_function_results(
    function_results: Any,
) -> List[Dict[str, Any]]:
    if not isinstance(function_results, dict):
        return []
    trace = function_results.get(TRACE_AGENT_KEY)
    if isinstance(trace, list):
        return trace
    return []


# اولویت استخراج متن نهایی از trace — فقط answer (Phase 1: answer-channel gate).
#
# قبلاً "explored" هم fallback بود و خلاصهٔ خام ابزارها (Markdown با ####)
# می‌توانست به‌جای پاسخ نهایی نمایش داده شود. explored/thought شواهد خام هستند،
# نه پاسخ نهایی؛ برای تولید پاسخ باید یک synthesis واقعی (LLM یا answer step)
# روی آن‌ها انجام شود — به extract_explored_context_for_synthesis نگاه کنید.
TRACE_CONTENT_FALLBACK_KINDS: tuple[str, ...] = (
    "answer",
)


def _is_valid_trace_answer_fallback(body: str, kind: str, *, min_body_len: int) -> bool:
    if not body:
        return False
    return len(body) >= min_body_len


def extract_final_content_from_trace(
    trace_steps: Optional[List[Dict[str, Any]]],
    *,
    min_body_len: int = 20,
) -> str:
    """متن قابل‌نمایش از trace agent (برای persist و fallback پاسخ).

    فقط از گام‌های kind="answer" استفاده می‌کند؛ narrative/explored/thought
    هرگز مستقیماً پاسخ نهایی نمی‌شوند (Phase 1 — answer channel gate).
    """
    if not trace_steps:
        return ""
    from app.services.ai.ai_content_sanitize import sanitize_assistant_content

    for kind in TRACE_CONTENT_FALLBACK_KINDS:
        for step in reversed(trace_steps):
            if step.get("kind") != kind:
                continue
            body = sanitize_assistant_content(
                (step.get("body_markdown") or "").strip()
            )
            if _is_valid_trace_answer_fallback(body, kind, min_body_len=min_body_len):
                return body
    return ""


def extract_explored_context_for_synthesis(
    trace_steps: Optional[List[Dict[str, Any]]],
    *,
    max_chars: int = 6000,
) -> str:
    """خلاصهٔ explored/thought/narrative مفید برای ساخت prompt سنتز نهایی.

    برخلاف extract_final_content_from_trace، این تابع صرفاً برای تغذیهٔ یک
    نوبت اضافی LLM (force-synthesis) استفاده می‌شود، نه نمایش مستقیم به کاربر.
    narrativeهای وضعیت («در حال…») عمداً حذف می‌شوند.
    """
    if not trace_steps:
        return ""
    from app.services.ai.ai_content_sanitize import sanitize_assistant_content
    from app.services.ai.ai_premature_answer import looks_like_status_narrative

    parts: List[str] = []
    total = 0
    for step in trace_steps:
        kind = step.get("kind")
        if kind not in ("explored", "thought", "narrative"):
            continue
        body = sanitize_assistant_content((step.get("body_markdown") or "").strip())
        if not body:
            continue
        if kind == "narrative" and looks_like_status_narrative(body):
            continue
        parts.append(body)
        total += len(body)
        if total >= max_chars:
            break
    joined = "\n\n".join(parts)
    return joined[:max_chars]


def extract_usable_narrative_for_answer(
    trace_steps: Optional[List[Dict[str, Any]]],
    *,
    min_body_len: int = 40,
) -> str:
    """آخرین narrative قابل‌قبول به‌عنوان پاسخ (نه status مثل «در حال…»).

    برای بازیابی وقتی wall-clock/budget قطع می‌شود ولی مدل قبلاً خلاصهٔ
    واقعی نوشته و فقط kind=answer ثبت نشده (مثل session 750).
    """
    if not trace_steps:
        return ""
    from app.services.ai.ai_content_sanitize import sanitize_assistant_content
    from app.services.ai.ai_premature_answer import looks_like_status_narrative

    for step in reversed(trace_steps):
        if step.get("kind") != "narrative":
            continue
        body = sanitize_assistant_content(
            (step.get("body_markdown") or "").strip()
        )
        if len(body) < min_body_len:
            continue
        if looks_like_status_narrative(body):
            continue
        return body
    return ""


def trace_has_unanswered_evidence(
    trace_steps: Optional[List[Dict[str, Any]]],
) -> bool:
    """آیا trace شواهد ابزار (explored/thought) دارد اما هنوز answer نهایی ندارد؟"""
    if not trace_steps:
        return False
    has_answer = any(step.get("kind") == "answer" for step in trace_steps)
    if has_answer:
        return False
    return any(step.get("kind") in ("explored", "thought") for step in trace_steps)


def merge_accumulated_and_trace_content(
    accumulated_content: str,
    trace_steps: Optional[List[Dict[str, Any]]],
) -> str:
    """ترکیب متن stream شده با fallback از trace."""
    from app.services.ai.ai_deliverable_answer import is_deliverable_answer

    text = (accumulated_content or "").strip()
    has_tool_evidence = bool(trace_steps) and any(
        step.get("kind") in ("explored", "thought", "tool", "narrative")
        for step in trace_steps
    )
    if text and is_deliverable_answer(
        text,
        needs_tools=has_tool_evidence,
        has_tool_evidence=has_tool_evidence,
    ):
        return accumulated_content
    synthesized = extract_final_content_from_trace(trace_steps)
    if synthesized:
        return synthesized
    usable = extract_usable_narrative_for_answer(trace_steps)
    return usable or (accumulated_content or "")
