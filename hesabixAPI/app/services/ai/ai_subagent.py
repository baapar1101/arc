"""اجرای موقت subagent برای سوال چنددامنه‌ای (AGT-06).

سقف محصول: حداکثر ۲ فرزند همزمان، ۴ نوبت ابزار، analyzer بدون write.
ذخیرهٔ run درون‌پردازه‌ای است (فاز ۰–۲)؛ جدول SQL موکول به persist بادوام.
"""
from __future__ import annotations

import asyncio
import logging
import time
import uuid
from dataclasses import dataclass, field
from typing import Any, Awaitable, Callable, Dict, List, Optional, Sequence

from app.services.ai.ai_constants import (
    AI_OPERATION_SUBAGENT,
    MAX_SUBAGENT_ITERATIONS,
    MAX_SUBAGENTS_PER_PARENT,
    SUBAGENT_TIMEOUT_SEC,
)
from app.services.ai.ai_ops_metrics import log_ai_event
from app.services.ai.ai_tool_intent import (
    estimate_query_complexity,
    matched_query_categories,
)
from app.services.ai.ai_write_guard import is_readonly_function, is_write_function
from app.services.ai.ai_subagent_sse import (
    emit_parent_subagent_event,
    remap_child_trace_event,
    subagent_card_event,
    subagent_step_id,
    synthetic_child_tool_events,
)

logger = logging.getLogger(__name__)

SPAWN_SUBAGENT_TOOL = "spawn_subagent"
AWAIT_SUBAGENT_TOOL = "await_subagent"
CANCEL_SUBAGENT_TOOL = "cancel_subagent"
SUBAGENT_TOOL_NAMES: frozenset[str] = frozenset(
    {SPAWN_SUBAGENT_TOOL, AWAIT_SUBAGENT_TOOL, CANCEL_SUBAGENT_TOOL}
)
_SUBAGENT_DOMAIN_CATEGORIES: frozenset[str] = frozenset(
    {
        "financial",
        "warehouse",
        "crm",
        "people",
        "tax",
        "projects",
        "customer_club",
        "integration",
    }
)

CompletionFn = Callable[..., Awaitable[Dict[str, Any]]]


@dataclass
class SubagentRun:
    subagent_id: str
    parent_session_id: Optional[int]
    goal: str
    status: str = "running"
    task: Optional[asyncio.Task] = None
    result: Optional[Dict[str, Any]] = None
    cancel_requested: bool = False
    created_at: float = field(default_factory=time.monotonic)


_runs: Dict[str, SubagentRun] = {}
_lock = asyncio.Lock()


def reset_subagent_runs_for_tests() -> None:
    _runs.clear()


def should_expose_subagent_tools(
    user_query: Optional[str],
    *,
    is_subagent: bool = False,
) -> bool:
    """سوال ساده spawn نمی‌بیند؛ فقط چنددامنه یا complex."""
    if is_subagent:
        return False
    complexity = estimate_query_complexity(user_query)
    if complexity == "simple":
        return False
    if complexity == "complex":
        return True
    domain = matched_query_categories(user_query) & _SUBAGENT_DOMAIN_CATEGORIES
    return len(domain) >= 2


def _function_name(item: Any) -> str:
    if not isinstance(item, dict):
        return ""
    return str((item.get("function") or {}).get("name") or item.get("name") or "")


def filter_subagent_tools(
    definitions: Sequence[Any],
    allowlist: Optional[Sequence[str]] = None,
    *,
    registry=None,
) -> List[Any]:
    """فرزند فقط read می‌بیند؛ spawn تو در تو و write حذف می‌شوند."""
    allowed = {str(n).strip() for n in (allowlist or ()) if str(n).strip()}
    out: List[Any] = []
    for item in definitions:
        name = _function_name(item)
        if not name or name in SUBAGENT_TOOL_NAMES:
            continue
        if allowed and name not in allowed:
            continue
        if is_write_function(name, registry):
            continue
        if not is_readonly_function(name, registry):
            fn = registry.get_function(name) if registry is not None else None
            if not bool(getattr(fn, "is_agent_internal", False)):
                continue
        out.append(item)
    return out


def _parse_allowlist(raw: Any) -> List[str]:
    if raw is None:
        return []
    if isinstance(raw, str):
        return [p.strip() for p in raw.split(",") if p.strip()]
    if isinstance(raw, Sequence) and not isinstance(raw, (bytes, bytearray)):
        return [str(item).strip() for item in raw if str(item).strip()]
    return []


def _envelope(
    *,
    subagent_id: str,
    status: str,
    goal: str,
    content: str = "",
    function_calls: Any = None,
    function_results: Any = None,
    citations: Any = None,
    error: Optional[str] = None,
    iterations: Optional[int] = None,
) -> Dict[str, Any]:
    return {
        "ok": error is None and status in {"completed", "cancelled"},
        "subagent_id": subagent_id,
        "status": status,
        "goal": goal,
        "content": content or "",
        "function_calls": function_calls or [],
        "function_results": function_results or {},
        "citations": citations or [],
        "iterations": iterations,
        "error": error,
    }


def _count_running(session_id: Optional[int]) -> int:
    n = 0
    for run in _runs.values():
        if run.status != "running":
            continue
        if session_id is None or run.parent_session_id == session_id:
            n += 1
    return n


def list_session_subagents(session_id: Optional[int]) -> List[Dict[str, Any]]:
    """وضعیت فرزندان یک جلسه برای UI."""
    out: List[Dict[str, Any]] = []
    for run in _runs.values():
        if session_id is not None and run.parent_session_id != session_id:
            continue
        out.append(
            {
                "subagent_id": run.subagent_id,
                "goal": run.goal,
                "status": run.status,
                "error": (run.result or {}).get("error") if run.result else None,
            }
        )
    return out


async def cancel_session_subagents(session_id: Optional[int]) -> int:
    """قطع همهٔ فرزندان در حال اجرای یک جلسهٔ والد."""
    cancelled = 0
    async with _lock:
        targets = [
            run
            for run in _runs.values()
            if run.status == "running"
            and (session_id is None or run.parent_session_id == session_id)
        ]
    for run in targets:
        if await _cancel_run(run):
            cancelled += 1
    if cancelled:
        log_ai_event(
            "subagent_session_cancelled",
            session_id=session_id,
            extra={"cancelled": cancelled},
        )
    return cancelled


async def _cancel_run(run: SubagentRun) -> bool:
    run.cancel_requested = True
    task = run.task
    if task is not None and not task.done():
        task.cancel()
        try:
            await task
        except (asyncio.CancelledError, Exception):
            pass
    if run.status == "running":
        run.status = "cancelled"
        run.result = _envelope(
            subagent_id=run.subagent_id,
            status="cancelled",
            goal=run.goal,
            error="SUBAGENT_CANCELLED",
        )
        return True
    return False


def cancel_subagent_sync(
    subagent_id: Optional[str],
    *,
    session_id: Optional[int] = None,
) -> Dict[str, Any]:
    """نسخهٔ همگام برای مسیر registry؛ cancel واقعی در async است."""
    sid = str(subagent_id or "").strip()
    if not sid:
        return {"ok": False, "error": "SUBAGENT_ID_REQUIRED"}
    run = _runs.get(sid)
    if run is None:
        return {"ok": False, "subagent_id": sid, "error": "SUBAGENT_NOT_FOUND"}
    if session_id is not None and run.parent_session_id not in (None, session_id):
        return {"ok": False, "subagent_id": sid, "error": "SUBAGENT_SESSION_MISMATCH"}
    run.cancel_requested = True
    task = run.task
    if task is not None and not task.done():
        task.cancel()
    run.status = "cancelled"
    envelope = _envelope(
        subagent_id=sid,
        status="cancelled",
        goal=run.goal,
        error="SUBAGENT_CANCELLED",
    )
    run.result = envelope
    log_ai_event("subagent_cancelled", session_id=session_id, extra={"subagent_id": sid})
    return envelope


async def cancel_subagent_async(
    subagent_id: Optional[str],
    *,
    session_id: Optional[int] = None,
) -> Dict[str, Any]:
    sid = str(subagent_id or "").strip()
    if not sid:
        return {"ok": False, "error": "SUBAGENT_ID_REQUIRED"}
    run = _runs.get(sid)
    if run is None:
        return {"ok": False, "subagent_id": sid, "error": "SUBAGENT_NOT_FOUND"}
    if session_id is not None and run.parent_session_id not in (None, session_id):
        return {"ok": False, "subagent_id": sid, "error": "SUBAGENT_SESSION_MISMATCH"}
    await _cancel_run(run)
    log_ai_event("subagent_cancelled", session_id=session_id, extra={"subagent_id": sid})
    envelope = run.result or _envelope(
        subagent_id=sid,
        status="cancelled",
        goal=run.goal,
        error="SUBAGENT_CANCELLED",
    )
    return envelope


async def await_subagent_async(
    subagent_id: Optional[str],
    *,
    session_id: Optional[int] = None,
    timeout_sec: float = SUBAGENT_TIMEOUT_SEC,
) -> Dict[str, Any]:
    sid = str(subagent_id or "").strip()
    if not sid:
        return {"ok": False, "error": "SUBAGENT_ID_REQUIRED"}
    run = _runs.get(sid)
    if run is None:
        return {"ok": False, "subagent_id": sid, "error": "SUBAGENT_NOT_FOUND"}
    if session_id is not None and run.parent_session_id not in (None, session_id):
        return {"ok": False, "subagent_id": sid, "error": "SUBAGENT_SESSION_MISMATCH"}
    if run.result is not None and run.status != "running":
        return run.result
    task = run.task
    if task is None:
        return run.result or _envelope(
            subagent_id=sid, status=run.status, goal=run.goal, error="SUBAGENT_NO_TASK"
        )
    try:
        await asyncio.wait_for(asyncio.shield(task), timeout=timeout_sec)
    except asyncio.TimeoutError:
        await _cancel_run(run)
        return run.result or _envelope(
            subagent_id=sid, status="cancelled", goal=run.goal, error="SUBAGENT_TIMEOUT"
        )
    except asyncio.CancelledError:
        parent_task = asyncio.current_task()
        parent_cancelled = bool(parent_task is not None and parent_task.cancelling())
        await _cancel_run(run)
        if parent_cancelled:
            raise
        return run.result or _envelope(
            subagent_id=sid, status="cancelled", goal=run.goal, error="SUBAGENT_CANCELLED"
        )
    return run.result or _envelope(
        subagent_id=sid, status=run.status, goal=run.goal
    )


def _extract_child_payload(raw: Dict[str, Any]) -> Dict[str, Any]:
    message = raw.get("message") if isinstance(raw.get("message"), dict) else {}
    content = str(
        raw.get("content")
        or raw.get("final_content")
        or (message.get("content") if message else "")
        or ""
    )
    calls = (
        raw.get("function_calls")
        or raw.get("_function_calls")
        or message.get("function_calls")
        or message.get("tool_calls")
        or []
    )
    results = (
        raw.get("function_results")
        or raw.get("_function_results")
        or {}
    )
    citations = raw.get("citations") or []
    if isinstance(results, dict) and not citations:
        citations = results.get("_citations") or []
    iterations = raw.get("iterations") or raw.get("iteration")
    return {
        "content": content,
        "function_calls": calls,
        "function_results": results,
        "citations": citations,
        "iterations": iterations,
    }


def has_running_session_subagents(session_id: Optional[int]) -> bool:
    if session_id is None:
        return False
    return any(
        run.status == "running" and run.parent_session_id == session_id
        for run in _runs.values()
    )


def _forward_child_event(
    parent: Any,
    event: Dict[str, Any],
    *,
    subagent_id: str,
    parent_step_id: str,
) -> None:
    remapped = remap_child_trace_event(
        event, subagent_id=subagent_id, parent_step_id=parent_step_id
    )
    if remapped:
        emit_parent_subagent_event(parent, remapped)


async def _run_child_completion(
    parent: Any,
    *,
    goal: str,
    allowlist: List[str],
    max_iterations: int,
    completion_fn: Optional[CompletionFn],
    business_id: Optional[int],
    subagent_id: Optional[str] = None,
    parent_step_id: Optional[str] = None,
) -> Dict[str, Any]:
    if completion_fn is not None:
        raw = await completion_fn(
            goal=goal,
            allowlist=allowlist,
            max_iterations=max_iterations,
            business_id=business_id,
        )
        if subagent_id and parent_step_id:
            payload = _extract_child_payload(raw if isinstance(raw, dict) else {})
            for ev in synthetic_child_tool_events(
                subagent_id=subagent_id,
                parent_step_id=parent_step_id,
                function_calls=payload.get("function_calls"),
            ):
                emit_parent_subagent_event(parent, ev)
        return raw

    from adapters.db.session import get_db_session
    from app.services.ai.ai_service import AIService
    from app.services.ai.ai_stream_aggregate import aggregate_chat_completion_stream
    from app.services.ai.function_registry import registry

    with get_db_session() as child_db:
        child = AIService(child_db, parent.ctx, business_id=business_id or parent.business_id)
        child._subagent_depth = getattr(parent, "_subagent_depth", 0) + 1
        requested = getattr(parent, "get_requested_model_code", None)
        if callable(requested):
            code = requested()
            if code:
                child.set_request_model(code)
        child.set_routing_context(
            operation=AI_OPERATION_SUBAGENT,
            user_query=goal,
            needs_tools=True,
        )
        tools = child.get_available_functions(
            session_business_id=business_id or parent.business_id,
            user_query=goal,
            execution_mode="analyzer",
            session_id=None,
        )
        tools = filter_subagent_tools(tools, allowlist, registry=registry)

        async def _tee():
            async for chunk in child.chat_completion_stream(
                messages=[{"role": "user", "content": goal}],
                tools=tools,
                use_function_calling=bool(tools),
                execution_mode="analyzer",
                approve_writes=False,
                max_iterations=max_iterations,
                iteration_cap=max_iterations,
                session_business_id=business_id or parent.business_id,
                session_id=None,
                user_query=goal,
            ):
                if (
                    subagent_id
                    and parent_step_id
                    and chunk.get("event") == "trace_step"
                ):
                    _forward_child_event(
                        parent,
                        chunk,
                        subagent_id=subagent_id,
                        parent_step_id=parent_step_id,
                    )
                yield chunk

        return await aggregate_chat_completion_stream(_tee())


async def spawn_subagent_async(
    parent: Any,
    arguments: Dict[str, Any],
    *,
    session_id: Optional[int] = None,
    business_id: Optional[int] = None,
    completion_fn: Optional[CompletionFn] = None,
) -> Dict[str, Any]:
    if getattr(parent, "_subagent_depth", 0) >= 1:
        return {"ok": False, "error": "SUBAGENT_NESTING_FORBIDDEN"}

    goal = str(arguments.get("goal") or arguments.get("task") or "").strip()
    if not goal:
        return {"ok": False, "error": "SUBAGENT_GOAL_REQUIRED"}

    allowlist = _parse_allowlist(
        arguments.get("tool_allowlist") or arguments.get("allowlist")
    )
    wait = arguments.get("wait", False)
    if isinstance(wait, str):
        wait = wait.strip().lower() not in {"false", "0", "no"}
    else:
        wait = bool(wait)

    requested_iters = arguments.get("max_iterations")
    try:
        max_iterations = int(requested_iters) if requested_iters is not None else MAX_SUBAGENT_ITERATIONS
    except (TypeError, ValueError):
        max_iterations = MAX_SUBAGENT_ITERATIONS
    max_iterations = max(1, min(max_iterations, MAX_SUBAGENT_ITERATIONS))

    async with _lock:
        if _count_running(session_id) >= MAX_SUBAGENTS_PER_PARENT:
            return {
                "ok": False,
                "error": "SUBAGENT_LIMIT",
                "max": MAX_SUBAGENTS_PER_PARENT,
            }
        subagent_id = uuid.uuid4().hex[:16]
        run = SubagentRun(
            subagent_id=subagent_id,
            parent_session_id=session_id,
            goal=goal,
        )
        _runs[subagent_id] = run

    card_id = subagent_step_id(subagent_id)
    started = time.monotonic()
    emit_parent_subagent_event(
        parent,
        subagent_card_event(
            subagent_id=subagent_id,
            goal=goal,
            state="active",
        ),
    )

    def _elapsed_ms() -> int:
        return int((time.monotonic() - started) * 1000)

    def _emit_card(state: str, envelope: Dict[str, Any]) -> None:
        emit_parent_subagent_event(
            parent,
            subagent_card_event(
                subagent_id=subagent_id,
                goal=goal,
                state=state,
                body=str(envelope.get("content") or envelope.get("error") or goal),
                elapsed_ms=_elapsed_ms(),
                error=envelope.get("error"),
            ),
        )

    async def _execute() -> Dict[str, Any]:
        try:
            raw = await asyncio.wait_for(
                _run_child_completion(
                    parent,
                    goal=goal,
                    allowlist=allowlist,
                    max_iterations=max_iterations,
                    completion_fn=completion_fn,
                    business_id=business_id,
                    subagent_id=subagent_id,
                    parent_step_id=card_id,
                ),
                timeout=SUBAGENT_TIMEOUT_SEC,
            )
            payload = _extract_child_payload(raw if isinstance(raw, dict) else {})
            envelope = _envelope(
                subagent_id=subagent_id,
                status="completed",
                goal=goal,
                **payload,
            )
            run.status = "completed"
            run.result = envelope
            _emit_card("done", envelope)
            return envelope
        except asyncio.CancelledError:
            run.status = "cancelled"
            envelope = _envelope(
                subagent_id=subagent_id,
                status="cancelled",
                goal=goal,
                error="SUBAGENT_CANCELLED",
            )
            run.result = envelope
            _emit_card("error", envelope)
            raise
        except asyncio.TimeoutError:
            run.status = "cancelled"
            envelope = _envelope(
                subagent_id=subagent_id,
                status="cancelled",
                goal=goal,
                error="SUBAGENT_TIMEOUT",
            )
            run.result = envelope
            _emit_card("error", envelope)
            return envelope
        except Exception as exc:
            logger.exception("subagent %s failed: %s", subagent_id, exc)
            run.status = "failed"
            envelope = _envelope(
                subagent_id=subagent_id,
                status="failed",
                goal=goal,
                error=str(exc),
            )
            run.result = envelope
            _emit_card("error", envelope)
            return envelope

    task = asyncio.create_task(_execute())
    run.task = task
    log_ai_event(
        "subagent_spawned",
        business_id=business_id,
        session_id=session_id,
        extra={
            "subagent_id": subagent_id,
            "wait": bool(wait),
            "allowlist_size": len(allowlist),
            "max_iterations": max_iterations,
        },
    )
    parent_task = asyncio.current_task()
    if parent_task is not None:
        def _on_parent_done(done_task: asyncio.Task) -> None:
            if done_task.cancelled() and run.status == "running":
                run.cancel_requested = True
                if run.task is not None and not run.task.done():
                    run.task.cancel()

        parent_task.add_done_callback(_on_parent_done)

    if not wait:
        return {
            "ok": True,
            "subagent_id": subagent_id,
            "status": "running",
            "goal": goal,
            "wait": False,
        }
    try:
        return await task
    except asyncio.CancelledError:
        parent_task = asyncio.current_task()
        parent_cancelled = bool(parent_task is not None and parent_task.cancelling())
        await _cancel_run(run)
        if parent_cancelled:
            raise
        return run.result or _envelope(
            subagent_id=subagent_id,
            status="cancelled",
            goal=goal,
            error="SUBAGENT_CANCELLED",
        )
