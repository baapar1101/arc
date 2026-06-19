"""
کنترل‌گر بودجهٔ یکپارچهٔ حلقهٔ Agent.

«سقف مراحل استدلال» یک عدد ساده نیست؛ در ابزارهای درجه‌یک، سقف چندبعدی است:
  - تعداد نوبت‌های LLM ↔ tool (iterations)
  - بودجهٔ توکن کل مصرف‌شده (input + output)
  - سقف زمان دیوار (wall-clock)
  - توقف زودهنگام در صورت بازده نزولی (نوبت‌های بی‌حاصل متوالی)

این ماژول این چهار بُعد را در یک شیء واحد جمع می‌کند تا حلقهٔ agent در هر نوبت
فقط یک‌بار `check()` را صدا بزند و در صورت رسیدن به هر سقف، با دلیل مشخص متوقف شود.
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Optional

from app.services.ai.ai_constants import (
    AGENT_BUDGET_ABSOLUTE_MAX_ITERATIONS,
    AGENT_BUDGET_EXTENSION_ITERATIONS,
    AGENT_BUDGET_EXTENSIONS_MAX,
    MAX_AGENT_ITERATIONS,
    MAX_UNPRODUCTIVE_ROUNDS,
    QUERY_COMPLEXITY_TOKEN_BUDGET,
    QUERY_COMPLEXITY_WALL_CLOCK_SEC,
)

# دلایل توقف (برای trace و پیام کاربر)
STOP_REASON_ITERATIONS = "max_iterations"
STOP_REASON_TOKENS = "token_budget"
STOP_REASON_WALL_CLOCK = "wall_clock"
STOP_REASON_UNPRODUCTIVE = "diminishing_returns"

AGENT_BUDGET_STORAGE_KEY = "_agent_budget"


@dataclass
class BudgetStatus:
    """نتیجهٔ بررسی بودجه در یک نوبت."""

    stop: bool
    reason: Optional[str] = None
    message_fa: Optional[str] = None


@dataclass
class AgentBudget:
    """سقف چندبعدی برای یک پاسخ assistant."""

    max_iterations: int = MAX_AGENT_ITERATIONS
    base_max_iterations: int = 0
    max_total_tokens: Optional[int] = None
    wall_clock_sec: Optional[float] = None
    max_unproductive_rounds: int = MAX_UNPRODUCTIVE_ROUNDS
    max_extensions: int = AGENT_BUDGET_EXTENSIONS_MAX
    extension_iterations: int = AGENT_BUDGET_EXTENSION_ITERATIONS
    absolute_max_iterations: int = AGENT_BUDGET_ABSOLUTE_MAX_ITERATIONS

    # وضعیت runtime
    tokens_used: int = 0
    unproductive_rounds: int = 0
    extensions_granted: int = 0
    started_at: float = field(default_factory=time.monotonic)

    def __post_init__(self) -> None:
        if self.base_max_iterations <= 0:
            self.base_max_iterations = self.max_iterations

    def reset_clock(self) -> None:
        self.started_at = time.monotonic()

    def add_tokens(self, total_tokens: Optional[int]) -> None:
        if total_tokens and total_tokens > 0:
            self.tokens_used += int(total_tokens)

    def note_round(self, *, productive: bool) -> None:
        """ثبت بازده یک نوبت: productive=True یعنی دادهٔ جدید/مفید آمده است."""
        if productive:
            self.unproductive_rounds = 0
        else:
            self.unproductive_rounds += 1

    @property
    def elapsed_sec(self) -> float:
        return time.monotonic() - self.started_at

    def remaining_iterations(self, current_iteration: int) -> int:
        return max(0, self.max_iterations - current_iteration)

    def try_extend(self) -> bool:
        """تمدید سقف نوبت در صورت نیاز به تحلیل بیشتر (با سقف مطلق)."""
        if self.extensions_granted >= self.max_extensions:
            return False
        new_max = self.max_iterations + self.extension_iterations
        if new_max > self.absolute_max_iterations:
            new_max = self.absolute_max_iterations
        if new_max <= self.max_iterations:
            return False
        self.max_iterations = new_max
        self.extensions_granted += 1
        return True

    def check(self, current_iteration: int) -> BudgetStatus:
        """آیا حلقه باید پیش از نوبت بعدی متوقف شود؟"""
        if current_iteration >= self.max_iterations:
            return BudgetStatus(
                stop=True,
                reason=STOP_REASON_ITERATIONS,
                message_fa=(
                    f"به حداکثر تعداد مراحل تحلیل ({self.max_iterations}) رسیدم."
                ),
            )
        if (
            self.max_total_tokens is not None
            and self.tokens_used >= self.max_total_tokens
        ):
            return BudgetStatus(
                stop=True,
                reason=STOP_REASON_TOKENS,
                message_fa=(
                    "به سقف بودجهٔ توکن این پاسخ رسیدم؛ "
                    "برای ادامه سوال را در چند پیام کوتاه‌تر بپرسید."
                ),
            )
        if (
            self.wall_clock_sec is not None
            and self.elapsed_sec >= self.wall_clock_sec
        ):
            return BudgetStatus(
                stop=True,
                reason=STOP_REASON_WALL_CLOCK,
                message_fa=(
                    "زمان مجاز برای تحلیل این پاسخ به پایان رسید؛ "
                    "با داده‌های جمع‌آوری‌شده ادامه می‌دهم."
                ),
            )
        if (
            self.max_unproductive_rounds > 0
            and self.unproductive_rounds >= self.max_unproductive_rounds
        ):
            return BudgetStatus(
                stop=True,
                reason=STOP_REASON_UNPRODUCTIVE,
                message_fa=(
                    "چند مرحلهٔ اخیر دادهٔ تازه‌ای اضافه نکرد؛ "
                    "با شواهد موجود پاسخ می‌دهم."
                ),
            )
        return BudgetStatus(stop=False)


def build_agent_budget(
    complexity: str,
    *,
    max_iterations: int,
    enforce_token_budget: bool = True,
    enforce_wall_clock: bool = True,
) -> AgentBudget:
    """ساخت بودجه بر اساس پیچیدگی سوال و سقف نوبت محاسبه‌شده."""
    token_budget = (
        QUERY_COMPLEXITY_TOKEN_BUDGET.get(complexity)
        if enforce_token_budget
        else None
    )
    wall_clock = (
        QUERY_COMPLEXITY_WALL_CLOCK_SEC.get(complexity)
        if enforce_wall_clock
        else None
    )
    return AgentBudget(
        max_iterations=max_iterations,
        max_total_tokens=token_budget,
        wall_clock_sec=wall_clock,
    )


def budget_snapshot(
    budget: AgentBudget,
    *,
    iteration: int = 0,
    reasoning_effort: Optional[str] = None,
    stop_reason: Optional[str] = None,
    stop_message_fa: Optional[str] = None,
) -> dict[str, object]:
    """نمای لحظه‌ای بودجه برای SSE و ذخیره در function_results."""
    snap: dict[str, object] = {
        "iteration": iteration,
        "max_iterations": budget.max_iterations,
        "base_max_iterations": budget.base_max_iterations,
        "tokens_used": budget.tokens_used,
        "max_total_tokens": budget.max_total_tokens,
        "elapsed_sec": round(budget.elapsed_sec, 1),
        "wall_clock_sec": budget.wall_clock_sec,
        "unproductive_rounds": budget.unproductive_rounds,
        "max_unproductive_rounds": budget.max_unproductive_rounds,
        "extensions_granted": budget.extensions_granted,
        "max_extensions": budget.max_extensions,
    }
    if reasoning_effort:
        snap["reasoning_effort"] = reasoning_effort
    if stop_reason:
        snap["stop_reason"] = stop_reason
    if stop_message_fa:
        snap["stop_message_fa"] = stop_message_fa
    return snap
