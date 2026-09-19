"""
وضعیت اجرای agent (Agent Run State) — checkpoint سبک + ادامهٔ واقعی.

شناسهٔ اجرا (run_id) و فاز جاری برای trace/agent_budget و جدول ai_agent_runs.
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from typing import Any, Iterable, Optional

from app.services.ai.ai_budget import (
    STOP_REASON_ITERATIONS,
    STOP_REASON_TOKENS,
    STOP_REASON_UNPRODUCTIVE,
    STOP_REASON_WALL_CLOCK,
)

# فازهای اجرای یک پاسخ agent
AGENT_RUN_PHASE_GATHER_CONTEXT = "gather_context"
AGENT_RUN_PHASE_AGENT_LOOP = "agent_loop"
AGENT_RUN_PHASE_SYNTHESIZE = "synthesize"
AGENT_RUN_PHASE_PERSIST = "persist"
AGENT_RUN_PHASE_DONE = "done"
AGENT_RUN_PHASE_ERROR = "error"
AGENT_RUN_PHASE_INTERRUPTED = "interrupted"

AGENT_RUN_PHASES: frozenset[str] = frozenset(
    {
        AGENT_RUN_PHASE_GATHER_CONTEXT,
        AGENT_RUN_PHASE_AGENT_LOOP,
        AGENT_RUN_PHASE_SYNTHESIZE,
        AGENT_RUN_PHASE_PERSIST,
        AGENT_RUN_PHASE_DONE,
        AGENT_RUN_PHASE_ERROR,
        AGENT_RUN_PHASE_INTERRUPTED,
    }
)

AGENT_RUN_STATUS_RUNNING = "running"
AGENT_RUN_STATUS_INTERRUPTED = "interrupted"
AGENT_RUN_STATUS_BUDGET_EXHAUSTED = "budget_exhausted"
AGENT_RUN_STATUS_AWAITING_APPROVAL = "awaiting_approval"
AGENT_RUN_STATUS_COMPLETED = "completed"
AGENT_RUN_STATUS_ERROR = "error"

STOP_REASON_DISCONNECT = "disconnect"

RESUMABLE_STOP_REASONS: frozenset[str] = frozenset(
    {
        STOP_REASON_ITERATIONS,
        STOP_REASON_TOKENS,
        STOP_REASON_WALL_CLOCK,
        STOP_REASON_UNPRODUCTIVE,
        STOP_REASON_DISCONNECT,
    }
)


def new_agent_run_id() -> str:
    """شناسهٔ یکتای کوتاه برای یک اجرای agent (یک پاسخ streaming)."""
    return uuid.uuid4().hex[:16]


def is_resumable_stop_reason(stop_reason: Optional[str]) -> bool:
    if not stop_reason:
        return False
    return str(stop_reason) in RESUMABLE_STOP_REASONS


def status_for_stop(
    *,
    stop_reason: Optional[str] = None,
    awaiting_approval: bool = False,
    error: bool = False,
    interrupted: bool = False,
    completed: bool = False,
) -> str:
    if error:
        return AGENT_RUN_STATUS_ERROR
    if awaiting_approval:
        return AGENT_RUN_STATUS_AWAITING_APPROVAL
    if interrupted or stop_reason == STOP_REASON_DISCONNECT:
        return AGENT_RUN_STATUS_INTERRUPTED
    if is_resumable_stop_reason(stop_reason):
        return AGENT_RUN_STATUS_BUDGET_EXHAUSTED
    if completed:
        return AGENT_RUN_STATUS_COMPLETED
    return AGENT_RUN_STATUS_RUNNING


@dataclass
class AgentRunState:
    """وضعیت یک اجرای agent — برای ردیابی، checkpoint و resume."""

    run_id: str = field(default_factory=new_agent_run_id)
    phase: str = AGENT_RUN_PHASE_GATHER_CONTEXT
    iteration: int = 0
    needs_tools: bool = False
    status: str = AGENT_RUN_STATUS_RUNNING
    stop_reason: Optional[str] = None

    def set_phase(self, phase: str) -> None:
        self.phase = phase

    def snapshot(self) -> dict[str, object]:
        can_continue = (
            self.status
            in (
                AGENT_RUN_STATUS_INTERRUPTED,
                AGENT_RUN_STATUS_BUDGET_EXHAUSTED,
            )
            or is_resumable_stop_reason(self.stop_reason)
        )
        return {
            "run_id": self.run_id,
            "phase": self.phase,
            "iteration": self.iteration,
            "needs_tools": self.needs_tools,
            "status": self.status,
            "stop_reason": self.stop_reason,
            "can_continue": bool(can_continue),
        }


def extract_agent_run_checkpoint(
    function_results: object,
) -> dict[str, object] | None:
    """خواندن checkpoint `_agent_run` از function_results ذخیره‌شده."""
    if not isinstance(function_results, dict):
        return None
    raw = function_results.get("_agent_run")
    if not isinstance(raw, dict):
        return None
    run_id = raw.get("run_id")
    if not run_id:
        return None
    return {
        "run_id": str(run_id),
        "phase": raw.get("phase"),
        "iteration": raw.get("iteration"),
        "needs_tools": bool(raw.get("needs_tools")),
        "status": raw.get("status"),
        "stop_reason": raw.get("stop_reason"),
        "can_continue": bool(raw.get("can_continue")),
        "tools_called": raw.get("tools_called") or [],
    }


def build_resume_continue_prompt(
    checkpoint: dict[str, object],
    *,
    tools_called: Optional[Iterable[str]] = None,
) -> str:
    """پیام ادامه برای وقتی کاربر می‌خواهد همان run را از checkpoint پی بگیرد."""
    iteration = checkpoint.get("iteration") or "?"
    run_id = checkpoint.get("run_id") or "?"
    stop_reason = checkpoint.get("stop_reason") or checkpoint.get("status") or ""
    names = list(tools_called or checkpoint.get("tools_called") or [])
    tools_part = ""
    if names:
        shown = ", ".join(str(n) for n in names[:40])
        tools_part = (
            f" ابزارهای قبلاً اجراشده: {shown}. "
            "این‌ها را تکرار نکن مگر داده عوض شده باشد."
        )
    stop_part = f" دلیل توقف قبلی: {stop_reason}." if stop_reason else ""
    return (
        "[agent_resume]\n"
        f"ادامهٔ تحلیل قبلی (run_id={run_id}, iteration={iteration})."
        f"{stop_part}{tools_part} "
        "از یافته‌های قبلی در تاریخچه استفاده کن، ابزارهای تکراری را صدا نزن، "
        "و فقط دادهٔ ناقص را تکمیل کن؛ سپس پاسخ نهایی بده."
    )
