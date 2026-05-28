"""
تخمین و مدیریت بودجه context ارسالی به مدل.
"""
from __future__ import annotations

import logging
from typing import Any, Callable, Dict, List, Optional, Tuple

from app.services.ai.ai_constants import (
    CONTEXT_INPUT_TOKEN_BUDGET,
    CONTEXT_KEEP_HEAD_MESSAGES,
    CONTEXT_KEEP_RECENT_MESSAGES,
    CONTEXT_SUMMARIZE_THRESHOLD_RATIO,
)
from app.services.ai.ai_message_budget import trim_messages_for_llm, trim_system_prompt

logger = logging.getLogger(__name__)

SummarizeFn = Callable[[List[Dict[str, Any]]], str]


def estimate_text_tokens(provider: Any, text: str) -> int:
    if not text:
        return 0
    if provider is not None and hasattr(provider, "estimate_tokens"):
        return int(provider.estimate_tokens(text))
    return max(1, len(text) // 4)


def estimate_messages_tokens(
    messages: List[Dict[str, Any]],
    provider: Any = None,
) -> int:
    total = 0
    for msg in messages:
        content = msg.get("content")
        if isinstance(content, str):
            total += estimate_text_tokens(provider, content)
        elif content is not None:
            total += estimate_text_tokens(provider, str(content))
        tool_calls = msg.get("tool_calls")
        if tool_calls:
            total += estimate_text_tokens(provider, str(tool_calls))
    return total


def compute_context_usage(
    messages: List[Dict[str, Any]],
    provider: Any = None,
    budget_tokens: int = CONTEXT_INPUT_TOKEN_BUDGET,
) -> Dict[str, Any]:
    estimated = estimate_messages_tokens(messages, provider)
    budget = max(1, int(budget_tokens))
    ratio = min(1.0, estimated / budget)
    return {
        "estimated_tokens": estimated,
        "budget_tokens": budget,
        "usage_ratio": round(ratio, 4),
        "usage_percent": round(ratio * 100, 1),
        "should_summarize": ratio >= CONTEXT_SUMMARIZE_THRESHOLD_RATIO,
    }


def is_context_overflow_error(exc: BaseException) -> bool:
    msg = str(exc).lower()
    if "context length" in msg and ("exceed" in msg or "too long" in msg):
        return True
    if "maximum context" in msg:
        return True
    if "max_model_len" in msg:
        return True
    if "token limit" in msg and "exceed" in msg:
        return True
    code = getattr(exc, "code", None) or getattr(exc, "error_code", None)
    if code == "AI_INVALID_MAX_TOKENS" and "context" in msg:
        return True
    return False


def _split_history_messages(
    messages: List[Dict[str, Any]],
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], List[Dict[str, Any]], List[Dict[str, Any]]]:
    """system, head, middle, tail"""
    system_msgs = [m for m in messages if m.get("role") == "system"]
    rest = [m for m in messages if m.get("role") != "system"]
    if len(rest) <= CONTEXT_KEEP_HEAD_MESSAGES + CONTEXT_KEEP_RECENT_MESSAGES:
        return system_msgs, rest, [], []

    head = rest[:CONTEXT_KEEP_HEAD_MESSAGES]
    tail = rest[-CONTEXT_KEEP_RECENT_MESSAGES:]
    middle = rest[CONTEXT_KEEP_HEAD_MESSAGES : -CONTEXT_KEEP_RECENT_MESSAGES]
    return system_msgs, head, middle, tail


def compress_history_messages(
    messages: List[Dict[str, Any]],
    summarize_fn: Optional[SummarizeFn] = None,
    *,
    force: bool = False,
) -> Tuple[List[Dict[str, Any]], bool]:
    """
    جایگزینی بخش میانی تاریخچه با یک پیام خلاصه.
    Returns: (messages, summarized_flag)
    """
    system_msgs, head, middle, tail = _split_history_messages(messages)
    if not middle and force:
        rest = [m for m in messages if m.get("role") != "system"]
        if len(rest) > 1:
            head = []
            middle = rest[:-1]
            tail = rest[-1:]
        else:
            return messages, False
    elif not middle:
        return messages, False

    if summarize_fn:
        try:
            summary_text = (summarize_fn(middle) or "").strip()
        except Exception as exc:
            logger.warning("LLM history summarize failed, using fallback: %s", exc)
            summary_text = ""
    else:
        summary_text = ""

    if not summary_text:
        from app.services.ai.ai_history_summarizer import build_rule_based_history_summary

        summary_text = build_rule_based_history_summary(middle)

    if not summary_text:
        return messages, False

    summary_msg = {
        "role": "user",
        "content": (
            "[خلاصهٔ خودکار مکالمهٔ قبلی — برای ادامهٔ گفت‌وگو از این بخش استفاده کن]\n"
            f"{summary_text}"
        ),
    }
    compressed = system_msgs + head + [summary_msg] + tail
    return compressed, True


def prepare_messages_for_context(
    system_prompt: str,
    messages: List[Dict[str, Any]],
    provider: Any = None,
    *,
    budget_tokens: int = CONTEXT_INPUT_TOKEN_BUDGET,
    summarize_fn: Optional[SummarizeFn] = None,
    force_summarize: bool = False,
) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    """
    آماده‌سازی پیام‌ها: در صورت نزدیک شدن به سقف، خلاصه‌سازی تاریخچه و trim.
    """
    system_content = trim_system_prompt(system_prompt)
    bundled: List[Dict[str, Any]] = [
        {"role": "system", "content": system_content},
        *messages,
    ]

    usage = compute_context_usage(bundled, provider, budget_tokens)
    history_summarized = False

    if force_summarize or usage["should_summarize"]:
        bundled, history_summarized = compress_history_messages(
            bundled,
            summarize_fn,
            force=force_summarize,
        )
        usage = compute_context_usage(bundled, provider, budget_tokens)

    trimmed = trim_messages_for_llm(bundled)
    usage["history_summarized"] = history_summarized
    usage["message_count"] = len(trimmed)
    return trimmed, usage

