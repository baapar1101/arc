"""
ارزیابی ادامهٔ حلقهٔ agent — ترکیب قواعد سریع + تصمیم LLM (مسیر C).

وقتی مدل بدون tool call متن می‌دهد، باید تشخیص دهیم:
- آیا این پاسخ نهایی است؟
- یا فقط narration/planning و باید ادامه دهیم؟
"""
from __future__ import annotations

import asyncio
import json
import logging
import re
from dataclasses import dataclass
from typing import Any, Dict, Optional, TYPE_CHECKING

from sqlalchemy.orm import Session

from app.services.ai.ai_content_sanitize import text_announces_pending_tool_use
from app.services.ai.ai_exploration_service import (
    ObservationStore,
    is_substantive_text_answer,
    observation_store_has_evidence,
)

if TYPE_CHECKING:
    from app.services.ai.ai_goal_assessment import AgentGoalTracker, RoundAssessment

logger = logging.getLogger(__name__)

_LLM_JSON_BLOCK = re.compile(r"\{[\s\S]*\}")


@dataclass
class ContinuationAssessment:
    should_continue: bool
    goal_reached: bool
    reason_fa: Optional[str] = None
    source: str = "rules"  # rules | llm


def _build_evidence_summary(store: Optional[ObservationStore]) -> str:
    if store is None or not observation_store_has_evidence(store):
        return "(هنوز داده‌ای از ابزار جمع نشده)"
    parts: list[str] = []
    if store.bundles:
        parts.append(f"تعداد دستهٔ ابزار: {len(store.bundles)}")
    if store.thoughts:
        parts.append(store.thoughts[-1].body_markdown[:1200])
    return "\n".join(parts)[:2000]


def assess_continuation_rule_based(
    *,
    round_text: str,
    user_query: Optional[str] = None,
    observation_store: Optional[ObservationStore] = None,
    rule_assessment: Optional["RoundAssessment"] = None,
    iteration: int = 0,
    max_iterations: int = 1,
) -> ContinuationAssessment:
    """مسیر سریع — موارد قطعی بدون فراخوانی LLM."""
    text = (round_text or "").strip()
    had_evidence = (
        observation_store is not None
        and observation_store_has_evidence(observation_store)
    )

    if rule_assessment and rule_assessment.loop_detected:
        return ContinuationAssessment(
            should_continue=False,
            goal_reached=False,
            reason_fa=rule_assessment.reason_fa,
            source="rules",
        )

    if text_announces_pending_tool_use(text):
        can_continue = iteration < max_iterations
        return ContinuationAssessment(
            should_continue=can_continue,
            goal_reached=False,
            reason_fa="مدل ابزار را اعلام کرده ولی هنوز اجرا نشده.",
            source="rules",
        )

    if rule_assessment and rule_assessment.should_continue:
        return ContinuationAssessment(
            should_continue=True,
            goal_reached=False,
            reason_fa=rule_assessment.reason_fa,
            source="rules",
        )

    if rule_assessment and rule_assessment.goal_reached:
        return ContinuationAssessment(
            should_continue=False,
            goal_reached=True,
            reason_fa=rule_assessment.reason_fa,
            source="rules",
        )

    if not had_evidence and is_substantive_text_answer(text):
        return ContinuationAssessment(
            should_continue=False,
            goal_reached=True,
            reason_fa="پاسخ متنی کامل بدون نیاز به ابزار.",
            source="rules",
        )

    if not text and iteration >= max_iterations:
        return ContinuationAssessment(
            should_continue=False,
            goal_reached=False,
            reason_fa="بودجهٔ مراحل تمام شد.",
            source="rules",
        )

    # مبهم — نیاز به LLM
    return ContinuationAssessment(
        should_continue=iteration < max_iterations and bool(text or had_evidence),
        goal_reached=False,
        reason_fa=None,
        source="ambiguous",
    )


def _parse_llm_continuation_json(raw: str) -> Optional[ContinuationAssessment]:
    if not raw:
        return None
    match = _LLM_JSON_BLOCK.search(raw.strip())
    if not match:
        return None
    try:
        data = json.loads(match.group(0))
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    should_continue = bool(data.get("should_continue"))
    goal_reached = bool(data.get("goal_reached"))
    reason = data.get("reason") or data.get("reason_fa")
    return ContinuationAssessment(
        should_continue=should_continue,
        goal_reached=goal_reached and not should_continue,
        reason_fa=str(reason).strip() if reason else None,
        source="llm",
    )


async def assess_continuation_with_llm(
    provider: Any,
    model: str,
    *,
    user_query: Optional[str],
    round_text: str,
    round_reasoning: str = "",
    observation_store: Optional[ObservationStore] = None,
    rule_assessment: Optional["RoundAssessment"] = None,
    iteration: int = 0,
    max_iterations: int = 1,
    db: Optional[Session] = None,
    max_tokens: int = 200,
    temperature: float = 0.1,
) -> Optional[ContinuationAssessment]:
    """تصمیم LLM برای موارد مبهم (مسیر C)."""
    from app.services.ai.prompt_service import get_prompt_by_key

    evidence = _build_evidence_summary(observation_store)
    rule_hint = ""
    if rule_assessment and rule_assessment.reason_fa:
        rule_hint = f"\nارزیابی اولیه: {rule_assessment.reason_fa}"

    user_content = (
        f"سوال کاربر: {user_query or ''}\n"
        f"مرحله: {iteration}/{max_iterations}\n"
        f"متن assistant (بدون tool call): {round_text[:2000]}\n"
        f"استدلال مدل: {(round_reasoning or '')[:1500]}\n"
        f"شواهد جمع‌شده:\n{evidence}"
        f"{rule_hint}\n\n"
        "آیا agent باید ادامه دهد (ابزار بزند/کاوش کند) یا متوقف شود؟"
    )
    messages = [
        {"role": "system", "content": get_prompt_by_key(db, "aux.agent_continuation")},
        {"role": "user", "content": user_content},
    ]

    def _run() -> Dict[str, Any]:
        return provider.chat_completion(
            messages=messages,
            model=model,
            max_tokens=max_tokens,
            temperature=temperature,
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
        if not isinstance(content, str):
            return None
        parsed = _parse_llm_continuation_json(content)
        if parsed is None:
            return None
        if parsed.should_continue and iteration >= max_iterations:
            parsed.should_continue = False
            parsed.reason_fa = (
                parsed.reason_fa or "به سقف مراحل تحلیل رسیدیم."
            )
        return parsed
    except Exception as exc:
        logger.warning("LLM agent continuation assessment failed: %s", exc)
        return None


async def resolve_agent_continuation(
    *,
    provider: Optional[Any] = None,
    model: Optional[str] = None,
    user_query: Optional[str] = None,
    round_text: str,
    round_reasoning: str = "",
    observation_store: Optional[ObservationStore] = None,
    goal_tracker: Optional["AgentGoalTracker"] = None,
    iteration: int = 0,
    max_iterations: int = 1,
    db: Optional[Session] = None,
    use_llm: bool = True,
) -> ContinuationAssessment:
    """نقطهٔ ورود یکپارچه — قواعد سریع سپس LLM برای موارد مبهم."""
    from app.services.ai.ai_goal_assessment import RoundAssessment

    rule_assessment: Optional[RoundAssessment] = None
    if goal_tracker is not None:
        rule_assessment = goal_tracker.assess_after_text_round(
            round_text,
            user_query=user_query,
            observation_store=observation_store,
        )

    rules = assess_continuation_rule_based(
        round_text=round_text,
        user_query=user_query,
        observation_store=observation_store,
        rule_assessment=rule_assessment,
        iteration=iteration,
        max_iterations=max_iterations,
    )

    if rules.source != "ambiguous":
        return rules

    if (
        use_llm
        and provider is not None
        and model
        and iteration < max_iterations
    ):
        llm_result = await assess_continuation_with_llm(
            provider,
            model,
            user_query=user_query,
            round_text=round_text,
            round_reasoning=round_reasoning,
            observation_store=observation_store,
            rule_assessment=rule_assessment,
            iteration=iteration,
            max_iterations=max_iterations,
            db=db,
        )
        if llm_result is not None:
            if goal_tracker is not None and rule_assessment is not None:
                from app.services.ai.ai_goal_assessment import RoundAssessment

                goal_tracker.last_assessment = RoundAssessment(
                    goal_reached=llm_result.goal_reached,
                    should_continue=llm_result.should_continue,
                    confidence="medium",
                    reason_fa=llm_result.reason_fa,
                )
            return llm_result

    return rules
