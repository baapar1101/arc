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
    max_total_tokens: Optional[int] = None
    wall_clock_sec: Optional[float] = None
    max_unproductive_rounds: int = MAX_UNPRODUCTIVE_ROUNDS

    # وضعیت runtime
    tokens_used: int = 0
    unproductive_rounds: int = 0
    started_at: float = field(default_factory=time.monotonic)

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
