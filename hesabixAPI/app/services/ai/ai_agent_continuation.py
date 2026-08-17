"""
ارزیابی ادامهٔ agent — فقط سیگنال ساختاری (evidence)، بدون regex/LLM روی متن.

Plan C: متن بدون tool_call ≠ پاسخ نهایی مگر evidence کافی جمع شده باشد.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from app.services.ai.ai_exploration_service import (
    ObservationStore,
    observation_store_has_evidence,
)
from app.services.ai.ai_deliverable_answer import is_deliverable_answer
from app.services.ai.ai_tool_intent import query_expects_tool_use


def _round_text_is_deliverable(
    text: str,
    *,
    needs_tools: bool,
    had_evidence: bool,
) -> bool:
    stripped = (text or "").strip()
    if not stripped:
        return False
    return is_deliverable_answer(
        stripped,
        needs_tools=needs_tools,
        has_tool_evidence=had_evidence,
    )


@dataclass
class EvidenceContinuation:
    should_continue: bool
    goal_reached: bool
    reason_fa: Optional[str] = None


def assess_text_round_evidence(
    *,
    round_text: str,
    user_query: Optional[str] = None,
    observation_store: Optional[ObservationStore] = None,
    needs_tools: bool = True,
    tool_discovery: bool = False,
    session_has_open_todos: bool = False,
    prior_goal_reached: bool = False,
    prior_should_continue: bool = False,
    prior_loop_detected: bool = False,
) -> EvidenceContinuation:
    """تصمیم continue/stop صرفاً از evidence و نوع سوال — نه از الگوی متن."""
    text = (round_text or "").strip()
    had_evidence = (
        observation_store is not None
        and observation_store_has_evidence(observation_store)
    )

    if prior_loop_detected:
        return EvidenceContinuation(
            should_continue=False,
            goal_reached=False,
            reason_fa="حلقهٔ تکراری ابزار شناسایی شد.",
        )

    if session_has_open_todos:
        return EvidenceContinuation(
            should_continue=True,
            goal_reached=False,
            reason_fa="مراحل باز در برنامهٔ کاری جلسه باقی مانده.",
        )

    if tool_discovery:
        if text:
            return EvidenceContinuation(
                should_continue=False,
                goal_reached=True,
                reason_fa="فهرست ابزارها ارائه شد.",
            )
        return EvidenceContinuation(
            should_continue=True,
            goal_reached=False,
            reason_fa="پاسخ فهرست ابزارها هنوز کامل نشده.",
        )

    if had_evidence and prior_goal_reached and not prior_should_continue:
        return EvidenceContinuation(
            should_continue=False,
            goal_reached=True,
            reason_fa="هدف در نوبت قبلی محقق شده بود.",
        )

    if had_evidence and observation_store and observation_store.thoughts:
        last = observation_store.thoughts[-1]
        if last.confidence == "high" and not last.open_questions:
            if _round_text_is_deliverable(
                text, needs_tools=needs_tools, had_evidence=True
            ):
                return EvidenceContinuation(
                    should_continue=False,
                    goal_reached=True,
                    reason_fa="شواهد کافی و پاسخ تحویلی آماده است.",
                )
            return EvidenceContinuation(
                should_continue=True,
                goal_reached=False,
                reason_fa="شواهد کافی جمع شد؛ پاسخ نهایی هنوز سنتز نشده.",
            )
        if _round_text_is_deliverable(
            text, needs_tools=needs_tools, had_evidence=True
        ):
            return EvidenceContinuation(
                should_continue=False,
                goal_reached=True,
                reason_fa="پس از شواهد ابزار، پاسخ تحویلی آماده شد.",
            )
        return EvidenceContinuation(
            should_continue=True,
            goal_reached=False,
            reason_fa="هنوز سوالات باز یا پاسخ تحویلی آماده نیست.",
        )

    if had_evidence and _round_text_is_deliverable(
        text, needs_tools=needs_tools, had_evidence=True
    ):
        return EvidenceContinuation(
            should_continue=False,
            goal_reached=True,
            reason_fa="پس از شواهد ابزار، پاسخ تحویلی آماده شد.",
        )

    if had_evidence:
        return EvidenceContinuation(
            should_continue=True,
            goal_reached=False,
            reason_fa="شواهد ابزار موجود است؛ پاسخ نهایی هنوز سنتز نشده.",
        )

    if not had_evidence:
        if needs_tools:
            return EvidenceContinuation(
                should_continue=True,
                goal_reached=False,
                reason_fa=(
                    "برای این سوال دادهٔ ابزار لازم است؛ "
                    "tool_call API یا Harmony ارسال نشده."
                ),
            )
        if text:
            return EvidenceContinuation(
                should_continue=False,
                goal_reached=True,
                reason_fa="پاسخ گفت‌وگوی ساده بدون نیاز به ابزار.",
            )
        return EvidenceContinuation(
            should_continue=False,
            goal_reached=False,
            reason_fa="پاسخی دریافت نشد.",
        )

    return EvidenceContinuation(
        should_continue=needs_tools,
        goal_reached=not needs_tools and bool(text),
        reason_fa="ارزیابی evidence-based.",
    )


def resolve_needs_tools(
    user_query: Optional[str],
    history_messages: Optional[list] = None,
    *,
    tools_enabled: bool = True,
) -> bool:
    if not tools_enabled:
        return False
    return query_expects_tool_use(user_query, history_messages)
