"""
Agent trace — زنجیرهٔ مراحل قابل نمایش برای کاربر (شبیه Cursor).
"""
from __future__ import annotations

import json
from typing import Any, Dict, List, Optional

from app.services.ai.ai_tool_keys import tool_label_fa, tool_l10n_key

TRACE_AGENT_KEY = "_agent_trace"

# نگاشت step آماده‌سازی context به کلید l10n
CONTEXT_STEP_TITLE_KEYS: Dict[str, str] = {
    "loading_prompt": "aiStatusLoadingPrompt",
    "loading_insights": "aiStatusLoadingInsights",
    "loading_memory": "aiStatusLoadingMemory",
    "loading_attachments": "aiStatusLoadingAttachments",
    "loading_knowledge": "aiStatusLoadingKnowledge",
    "loading_connectors": "aiStatusLoadingConnectors",
}

TraceKind = str  # plan | narrative | tool | observation | plan_next | answer
TraceState = str  # active | done | error


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
) -> Dict[str, Any]:
    payload: Dict[str, Any] = {
        "event": "trace_step",
        "step_id": step_id,
        "kind": kind,
        "state": state,
    }
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
    if result is None:
        return "نتیجه‌ای برنگشت."
    if isinstance(result, dict):
        if result.get("error") == "APPROVAL_REQUIRED":
            return json.dumps(result, ensure_ascii=False)
        if "error" in result:
            return json.dumps({"error": result.get("error"), "message": result.get("message")}, ensure_ascii=False)
        compact: Dict[str, Any] = {}
        for key in ("message", "summary", "description", "total", "pagination"):
            if key in result:
                compact[key] = result[key]
        for key in ("items", "data", "results", "invoices", "products", "persons"):
            items = result.get(key)
            if isinstance(items, list):
                compact[key] = items[:15]
                compact[f"{key}_total"] = (
                    (result.get("pagination") or {}).get("total")
                    if isinstance(result.get("pagination"), dict)
                    else len(items)
                )
                if len(items) > 15:
                    compact[f"{key}_truncated"] = True
                break
        if compact:
            return json.dumps(compact, ensure_ascii=False)
        text = json.dumps(result, ensure_ascii=False)
        if len(text) > 4000:
            return text[:4000] + "…"
        return text
    if isinstance(result, list):
        preview = result[:15]
        payload: Dict[str, Any] = {"items": preview, "total": len(result)}
        if len(result) > 15:
            payload["truncated"] = True
        return json.dumps(payload, ensure_ascii=False)
    text = str(result)
    return text[:4000] + ("…" if len(text) > 4000 else "")


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

        # پیام مستقیم
        for key in ("message", "summary", "description"):
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


def merge_trace_into_function_results(
    function_results: Optional[Dict[str, Any]],
    trace_steps: List[Dict[str, Any]],
) -> Dict[str, Any]:
    merged = dict(function_results or {})
    if trace_steps:
        merged[TRACE_AGENT_KEY] = trace_steps
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
