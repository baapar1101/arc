"""متریک ارزیابی premature-final برای regression و مانیتورینگ (Phase 3).

این ماژول برای اسکن پیام‌های ذخیره‌شده یا fixtureهاست — نه مسیر runtime.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from app.services.ai.ai_premature_answer import looks_like_status_narrative
from app.services.ai.ai_tool_intent import query_expects_tool_use


def is_premature_final_answer(
    *,
    assistant_content: str,
    user_query: Optional[str],
    history_messages: Optional[List[dict]] = None,
    function_calls: Any = None,
    function_results: Any = None,
) -> bool:
    """آیا پاسخ assistant شبیه قفل شدن روی narrative وضعیت است؟"""
    if not looks_like_status_narrative(assistant_content):
        return False
    if not query_expects_tool_use(user_query, history_messages):
        return False
    has_tools = bool(function_calls)
    if isinstance(function_results, dict):
        has_tools = has_tools or any(
            not str(k).startswith("_") for k in function_results
        )
    # اگر ابزار واقعاً اجرا شده، narrative خام معمولاً premature نیست
    # (مگر explored-as-answer که جداگانه سنجیده می‌شود)
    if has_tools:
        return False
    return True


def score_premature_rate(cases: List[Dict[str, Any]]) -> Dict[str, float]:
    """نرخ premature روی لیستی از caseها با کلیدهای content/user_query/..."""
    if not cases:
        return {"total": 0.0, "premature": 0.0, "rate": 0.0}
    premature = 0
    for case in cases:
        if is_premature_final_answer(
            assistant_content=case.get("assistant_content") or case.get("content") or "",
            user_query=case.get("user_query"),
            history_messages=case.get("history_messages"),
            function_calls=case.get("function_calls"),
            function_results=case.get("function_results"),
        ):
            premature += 1
    total = len(cases)
    return {
        "total": float(total),
        "premature": float(premature),
        "rate": premature / total,
    }
