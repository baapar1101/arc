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
from typing import Any, Callable, Dict, List, Optional, TYPE_CHECKING

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

if TYPE_CHECKING:
    from app.services.ai.ai_session_todo_service import SessionTodoGoalState


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
        self.last_session_todo_state: Optional["SessionTodoGoalState"] = None

    def assess_after_tool_round(
        self,
        function_calls: List[Dict[str, Any]],
        function_results: Dict[str, Any],
        lookup_result: Callable[[Dict[str, Any], Dict[str, Any]], Any],
        *,
        user_query: Optional[str] = None,
        session_todo_state: Optional["SessionTodoGoalState"] = None,
    ) -> RoundAssessment:
        self.last_session_todo_state = session_todo_state
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
        elif session_todo_state and session_todo_state.has_plan:
            assessment = self._assess_with_session_plan(
                session_todo_state=session_todo_state,
                productive=productive,
                confidence=confidence,
                open_questions=open_questions,
                hypothesis=hypothesis,
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

    @staticmethod
    def _assess_with_session_plan(
        *,
        session_todo_state: "SessionTodoGoalState",
        productive: bool,
        confidence: str,
        open_questions: List[str],
        hypothesis: Optional[str],
    ) -> RoundAssessment:
        if session_todo_state.all_complete:
            return RoundAssessment(
                goal_reached=True,
                should_continue=False,
                confidence="high",
                reason_fa=(
                    f"همهٔ مراحل برنامه انجام شد ({session_todo_state.progress_label_fa})."
                ),
            )

        reason_parts = [
            f"برنامهٔ کاری: {session_todo_state.progress_label_fa} تکمیل شده",
        ]
        if session_todo_state.in_progress:
            reason_parts.append(
                f"{session_todo_state.in_progress} مرحله در حال اجرا"
            )
        if session_todo_state.pending:
            reason_parts.append(f"{session_todo_state.pending} مرحله باقی‌مانده")
        if session_todo_state.error_count:
            reason_parts.append(f"{session_todo_state.error_count} مرحله با خطا")

        plan_open_questions = list(open_questions)
        for title in session_todo_state.open_titles[:4]:
            marker = f"انجام: {title}"
            if marker not in plan_open_questions:
                plan_open_questions.append(marker)

        if not productive:
            return RoundAssessment(
                goal_reached=False,
                should_continue=True,
                confidence="low",
                open_questions=plan_open_questions[:6],
                reason_fa="خروجی ابزارها بی‌حاصل بود؛ مراحل باز برنامه هنوز مانده.",
            )

        return RoundAssessment(
            goal_reached=False,
            should_continue=True,
            confidence=confidence,
            open_questions=plan_open_questions[:6],
            reason_fa="؛ ".join(reason_parts),
        )

    def continue_context_for_llm(self) -> Optional[str]:
        if not self.last_assessment or not self.last_assessment.should_continue:
            return None
        parts = [
            "[agent_continue]",
            "بر اساس تحلیل تا اینجا، هنوز به هدف نرسیدیم.",
        ]
        if self.last_assessment.reason_fa:
            parts.append(f"**وضعیت:** {self.last_assessment.reason_fa}")
        if self.last_session_todo_state and self.last_session_todo_state.has_open:
            from app.services.ai.ai_session_todo_service import (
                format_open_todos_for_agent_context,
            )

            plan_ctx = format_open_todos_for_agent_context(
                self.last_session_todo_state
            )
            if plan_ctx:
                parts.append(plan_ctx)
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
        if last.should_continue and not last.loop_detected:
            return True

    if goal_tracker and goal_tracker.last_session_todo_state:
        state = goal_tracker.last_session_todo_state
        if state.has_open:
            return budget.try_extend() if budget.remaining_iterations(iteration) <= 0 else True

    return False
