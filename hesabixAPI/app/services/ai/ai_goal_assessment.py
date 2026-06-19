"""
ارزیابی میانی هدف agent — ادامهٔ هوشمند + ضد loop.

پس از هر نوبت tool، سیستم بررسی می‌کند آیا به هدف رسیده‌ایم یا نه.
اگر نه و بودجه تمام شده باشد، تا سقف مطلق تمدید می‌شود؛
تکرار همان tool+args مانع تمدید و ادامه می‌شود.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional

from app.services.ai.ai_constants import AGENT_MAX_IDENTICAL_TOOL_REPEATS
from app.services.ai.ai_budget import AgentBudget, BudgetStatus, STOP_REASON_ITERATIONS
from app.services.ai.ai_exploration_service import (
    ExplorationBundle,
    ObservationStore,
    ToolObservation,
    assess_tool_round_productivity,
    build_thought_markdown_rule_based,
    should_continue_exploring,
)


@dataclass
class RoundAssessment:
    """نتیجهٔ ارزیابی یک نوبت tool."""

    goal_reached: bool
    should_continue: bool
    confidence: str = "medium"
    open_questions: List[str] = field(default_factory=list)
    reason_fa: Optional[str] = None
    loop_detected: bool = False


class ToolCallTracker:
    """ردگیری تکرار فراخوانی‌های یکسان برای جلوگیری از loop."""

    def __init__(self) -> None:
        self._counts: Dict[str, int] = {}

    @staticmethod
    def fingerprint(tool_name: str, arguments: Any) -> str:
        args = arguments if isinstance(arguments, dict) else {}
        canonical = json.dumps(
            {"n": tool_name, "a": args},
            sort_keys=True,
            ensure_ascii=False,
        )
        return hashlib.sha256(canonical.encode()).hexdigest()[:16]

    def record(self, function_calls: List[Dict[str, Any]]) -> int:
        """تعداد فراخوانی‌هایی که از آستانهٔ تکرار عبور کرده‌اند."""
        over_limit = 0
        for call in function_calls:
            fp = self.fingerprint(
                call.get("name", "unknown"),
                call.get("arguments", {}),
            )
            self._counts[fp] = self._counts.get(fp, 0) + 1
            if self._counts[fp] > AGENT_MAX_IDENTICAL_TOOL_REPEATS:
                over_limit += 1
        return over_limit

    def has_loop(self) -> bool:
        return any(
            count > AGENT_MAX_IDENTICAL_TOOL_REPEATS for count in self._counts.values()
        )


class AgentGoalTracker:
    """ارزیابی هدف per-request — مستقل از حالت exploration UI."""

    def __init__(self) -> None:
        self.tool_tracker = ToolCallTracker()
        self.last_assessment: Optional[RoundAssessment] = None

    def assess_after_tool_round(
        self,
        function_calls: List[Dict[str, Any]],
        function_results: Dict[str, Any],
        lookup_result: Callable[[Dict[str, Any], Dict[str, Any]], Any],
        *,
        user_query: Optional[str] = None,
    ) -> RoundAssessment:
        self.tool_tracker.record(function_calls)
        loop_detected = self.tool_tracker.has_loop()
        productive = assess_tool_round_productivity(
            function_calls, function_results, lookup_result
        )

        observations: List[ToolObservation] = []
        for call in function_calls:
            result = lookup_result(function_results, call)
            success = not (isinstance(result, dict) and result.get("error"))
            observations.append(
                ToolObservation(
                    tool_name=call.get("name", "unknown"),
                    arguments=call.get("arguments", {}) or {},
                    result=result,
                    success=success,
                )
            )

        bundle = ExplorationBundle(
            bundle_id="goal_assess",
            iteration=0,
            title="round",
            explore_targets=[],
            observations=observations,
        )
        _, hypothesis, confidence, open_questions = build_thought_markdown_rule_based(
            bundle, user_query
        )

        if loop_detected:
            assessment = RoundAssessment(
                goal_reached=False,
                should_continue=False,
                confidence="low",
                reason_fa="همان ابزار با همان پارامترها تکرار شد.",
                loop_detected=True,
            )
        elif not productive:
            assessment = RoundAssessment(
                goal_reached=False,
                should_continue=True,
                confidence="low",
                open_questions=open_questions
                or ["دادهٔ معناداری از ابزارها برنگشت."],
                reason_fa="خروجی ابزارها بی‌حاصل بود.",
            )
        elif confidence == "high" and not open_questions:
            assessment = RoundAssessment(
                goal_reached=True,
                should_continue=False,
                confidence=confidence,
                reason_fa="شواهد کافی جمع شد.",
            )
        elif confidence == "low" or open_questions:
            assessment = RoundAssessment(
                goal_reached=False,
                should_continue=True,
                confidence=confidence,
                open_questions=list(open_questions),
                reason_fa=hypothesis,
            )
        else:
            assessment = RoundAssessment(
                goal_reached=False,
                should_continue=False,
                confidence=confidence,
                open_questions=list(open_questions),
                reason_fa=hypothesis,
            )

        self.last_assessment = assessment
        return assessment

    def continue_context_for_llm(self) -> Optional[str]:
        if not self.last_assessment or not self.last_assessment.should_continue:
            return None
        parts = [
            "[agent_continue]",
            "بر اساس تحلیل تا اینجا، هنوز به هدف نرسیدیم.",
        ]
        if self.last_assessment.reason_fa:
            parts.append(f"**وضعیت:** {self.last_assessment.reason_fa}")
        if self.last_assessment.open_questions:
            parts.append("**سوالات باز:**")
            parts.extend(f"- {q}" for q in self.last_assessment.open_questions[:5])
        parts.append(
            "قبل از پاسخ نهایی، دادهٔ لازم را با ابزار مناسب جمع‌آوری کن "
            "(از تکرار همان فراخوانی‌های قبلی خودداری کن)."
        )
        return "\n".join(parts)


def try_extend_budget_for_goal(
    budget: AgentBudget, assessment: Optional[RoundAssessment]
) -> bool:
    """تمدید بودجه وقتی هدف محقق نشده و به سقف نوبت رسیده‌ایم."""
    if assessment is None or assessment.loop_detected:
        return False
    if assessment.goal_reached or not assessment.should_continue:
        return False
    return budget.try_extend()


def resolve_budget_gate(
    budget: AgentBudget,
    iteration: int,
    goal_tracker: Optional[AgentGoalTracker],
) -> BudgetStatus:
    """بررسی بودجه با امکان تمدید پویا پیش از توقف."""
    status = budget.check(iteration)
    if status.stop and status.reason == STOP_REASON_ITERATIONS:
        assessment = goal_tracker.last_assessment if goal_tracker else None
        if try_extend_budget_for_goal(budget, assessment):
            return BudgetStatus(stop=False)
    return status


def should_agent_continue_after_text_round(
    *,
    goal_tracker: Optional[AgentGoalTracker],
    observation_store: Optional[ObservationStore],
    exploration_enabled: bool,
    iteration: int,
    budget: AgentBudget,
) -> bool:
    """ادامه پس از پاسخ متنی مدل (بدون tool call)."""
    if budget.remaining_iterations(iteration) <= 0:
        assessment = goal_tracker.last_assessment if goal_tracker else None
        if (
            exploration_enabled
            and observation_store is not None
            and should_continue_exploring(
                observation_store, iteration, budget.max_iterations
            )
        ):
            return budget.try_extend()
        return try_extend_budget_for_goal(budget, assessment)

    if exploration_enabled and observation_store is not None:
        return should_continue_exploring(
            observation_store, iteration, budget.max_iterations
        )

    if goal_tracker and goal_tracker.last_assessment:
        last = goal_tracker.last_assessment
        return last.should_continue and not last.loop_detected

    return False
