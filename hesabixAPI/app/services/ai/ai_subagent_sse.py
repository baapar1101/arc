"""رویدادهای SSE زیر-ایجنت — کارت زنده شبیه Task در Cursor."""
from __future__ import annotations

import asyncio
from typing import Any, Dict, List, Optional

from app.services.ai.ai_tool_keys import tool_label_fa, tool_l10n_key
from app.services.ai.ai_trace import trace_step

CHILD_FORWARD_KINDS = frozenset(
    {
        "tool",
        "observation",
        "plan",
        "plan_next",
        "explore",
        "explored",
        "thought",
        "narrative",
    }
)

LIFECYCLE_TOOLS = frozenset({"spawn_subagent", "await_subagent", "cancel_subagent"})


def parent_subagent_queue(parent: Any) -> Optional[asyncio.Queue]:
    q = getattr(parent, "_subagent_sse_queue", None)
    return q if isinstance(q, asyncio.Queue) else None


def emit_parent_subagent_event(parent: Any, event: Dict[str, Any]) -> None:
    q = parent_subagent_queue(parent)
    if q is None:
        return
    q.put_nowait(dict(event))


async def drain_parent_subagent_events(
    parent: Any,
    *,
    timeout: float = 0.0,
) -> List[Dict[str, Any]]:
    q = parent_subagent_queue(parent)
    if q is None:
        return []
    events: List[Dict[str, Any]] = []
    if timeout and timeout > 0:
        try:
            events.append(await asyncio.wait_for(q.get(), timeout=timeout))
        except asyncio.TimeoutError:
            return []
    while True:
        try:
            events.append(q.get_nowait())
        except asyncio.QueueEmpty:
            break
    return events


def subagent_step_id(subagent_id: str) -> str:
    return f"subagent_{subagent_id}"


def subagent_card_event(
    *,
    subagent_id: str,
    goal: str,
    state: str,
    body: str = "",
    elapsed_ms: Optional[int] = None,
    error: Optional[str] = None,
) -> Dict[str, Any]:
    title_goal = (goal or "").strip()[:120]
    body_md = (body or goal or "").strip()[:800]
    if error and not body_md:
        body_md = error
    return trace_step(
        subagent_step_id(subagent_id),
        "subagent",
        state,
        title_key="aiTraceSubagent",
        title_params={"goal": title_goal},
        body_markdown=body_md or None,
        tool="spawn_subagent",
        tool_key="aiToolSpawnSubagent",
        explore_target=subagent_id,
        subagent_id=subagent_id,
        elapsed_ms=elapsed_ms,
    )


def remap_child_trace_event(
    event: Dict[str, Any],
    *,
    subagent_id: str,
    parent_step_id: str,
) -> Optional[Dict[str, Any]]:
    """فقط گام‌های قابل‌نمایش فرزند را به تایم‌لاین تو در تو نگاشت می‌کند."""
    if not isinstance(event, dict):
        return None
    kind = event.get("kind")
    if event.get("event") not in (None, "trace_step"):
        return None
    if kind not in CHILD_FORWARD_KINDS:
        return None
    if event.get("parent_step_id"):
        return None
    tool = str(event.get("tool") or "")
    if tool in LIFECYCLE_TOOLS:
        return None
    orig = str(event.get("step_id") or "").strip() or "step"
    out = {k: v for k, v in event.items() if k != "event"}
    out["event"] = "trace_step"
    out["step_id"] = f"sa_{subagent_id}_{orig}"
    out["parent_step_id"] = parent_step_id
    out["subagent_id"] = subagent_id
    out["layer"] = "reasoning"
    out["visibility"] = out.get("visibility") or "user"
    return out


def synthetic_child_tool_events(
    *,
    subagent_id: str,
    parent_step_id: str,
    function_calls: Any,
) -> List[Dict[str, Any]]:
    events: List[Dict[str, Any]] = []
    if not isinstance(function_calls, list):
        return events
    for idx, call in enumerate(function_calls):
        if not isinstance(call, dict):
            continue
        name = str(call.get("name") or "").strip()
        if not name or name in LIFECYCLE_TOOLS:
            continue
        label = tool_label_fa(name)
        events.append(
            remap_child_trace_event(
                trace_step(
                    f"tool_{idx}",
                    "tool",
                    "done",
                    title_key="aiTraceRunningTool",
                    title_params={"toolName": label},
                    tool=name,
                    tool_key=tool_l10n_key(name),
                ),
                subagent_id=subagent_id,
                parent_step_id=parent_step_id,
            )
        )
    return [e for e in events if e]


__all__ = [
    "CHILD_FORWARD_KINDS",
    "LIFECYCLE_TOOLS",
    "drain_parent_subagent_events",
    "emit_parent_subagent_event",
    "parent_subagent_queue",
    "remap_child_trace_event",
    "subagent_card_event",
    "subagent_step_id",
    "synthetic_child_tool_events",
]
