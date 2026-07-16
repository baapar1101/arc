"""
وضعیت اجرای agent (Agent Run State) — گام سبک به‌سوی runtime بالغ‌تر.

این ماژول یک شناسهٔ اجرا (run_id) و فاز جاری (phase) را برای هر پاسخ
streaming فراهم می‌کند تا در trace/agent_budget و checkpoint ذخیره‌شده در
function_results قابل ردیابی باشد. عمداً یک FSM کامل نیست؛ فقط داده‌ی سبک
برای wiring در حلقهٔ موجود chat_completion_stream.
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass, field

# فازهای اجرای یک پاسخ agent
AGENT_RUN_PHASE_GATHER_CONTEXT = "gather_context"
AGENT_RUN_PHASE_AGENT_LOOP = "agent_loop"
AGENT_RUN_PHASE_SYNTHESIZE = "synthesize"
AGENT_RUN_PHASE_PERSIST = "persist"
AGENT_RUN_PHASE_DONE = "done"
AGENT_RUN_PHASE_ERROR = "error"

AGENT_RUN_PHASES: frozenset[str] = frozenset(
    {
        AGENT_RUN_PHASE_GATHER_CONTEXT,
        AGENT_RUN_PHASE_AGENT_LOOP,
        AGENT_RUN_PHASE_SYNTHESIZE,
        AGENT_RUN_PHASE_PERSIST,
        AGENT_RUN_PHASE_DONE,
        AGENT_RUN_PHASE_ERROR,
    }
)


def new_agent_run_id() -> str:
    """شناسهٔ یکتای کوتاه برای یک اجرای agent (یک پاسخ streaming)."""
    return uuid.uuid4().hex[:16]


@dataclass
class AgentRunState:
    """وضعیت سبک یک اجرای agent — برای ردیابی/دیباگ، نه یک FSM کامل."""

    run_id: str = field(default_factory=new_agent_run_id)
    phase: str = AGENT_RUN_PHASE_GATHER_CONTEXT
    iteration: int = 0
    needs_tools: bool = False

    def set_phase(self, phase: str) -> None:
        self.phase = phase

    def snapshot(self) -> dict[str, object]:
        return {
            "run_id": self.run_id,
            "phase": self.phase,
            "iteration": self.iteration,
            "needs_tools": self.needs_tools,
        }


def extract_agent_run_checkpoint(
    function_results: object,
) -> dict[str, object] | None:
    """خواندن checkpoint سبک `_agent_run` از function_results ذخیره‌شده.

    برای resume/ادامهٔ تحلیل در آینده — فعلاً فقط استخراج؛ UI ادامه هنوز
    جداگانه پیاده می‌شود.
    """
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
    }


def build_resume_continue_prompt(checkpoint: dict[str, object]) -> str:
    """پیام ادامه برای وقتی کاربر می‌خواهد همان run را از checkpoint پی بگیرد."""
    iteration = checkpoint.get("iteration") or "?"
    run_id = checkpoint.get("run_id") or "?"
    return (
        "[agent_resume]\n"
        f"ادامهٔ تحلیل قبلی (run_id={run_id}, iteration={iteration}). "
        "از یافته‌های قبلی استفاده کن، ابزارهای تکراری را صدا نزن، "
        "و فقط دادهٔ ناقص را تکمیل کن؛ سپس پاسخ نهایی بده."
    )
