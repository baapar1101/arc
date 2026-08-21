"""ذخیره و بازیابی checkpoint اجرای agent در جدول ai_agent_runs."""
from __future__ import annotations

import json
import logging
from datetime import datetime
from typing import Any, Optional

from sqlalchemy.orm import Session

from adapters.db.models.ai_agent_run import AIAgentRun, AIAgentRunStatus
from app.core.json_safe import json_dumps_safe
from app.services.ai.ai_agent_run import extract_agent_run_checkpoint

logger = logging.getLogger(__name__)


def _parse_json_list(raw: Optional[str]) -> list[str]:
    if not raw:
        return []
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return []
    if not isinstance(data, list):
        return []
    return [str(item) for item in data if item]


def tools_called_from_function_results(function_results: object) -> list[str]:
    if not isinstance(function_results, dict):
        return []
    names: list[str] = []
    seen: set[str] = set()
    for key, value in function_results.items():
        if str(key).startswith("_"):
            continue
        name = None
        if isinstance(value, dict) and value.get("name"):
            name = str(value.get("name"))
        elif isinstance(key, str):
            name = key
        if not name or name in seen:
            continue
        seen.add(name)
        names.append(name)
    return names


def upsert_agent_run(
    db: Session,
    *,
    run_id: str,
    session_id: int,
    user_id: int,
    business_id: Optional[int] = None,
    phase: Optional[str] = None,
    iteration: Optional[int] = None,
    needs_tools: Optional[bool] = None,
    status: Optional[str] = None,
    stop_reason: Optional[str] = None,
    tools_called: Optional[list[str]] = None,
    budget: Optional[dict[str, Any]] = None,
    last_event_id: Optional[int] = None,
    origin_message_id: Optional[int] = None,
    extra: Optional[dict[str, Any]] = None,
) -> AIAgentRun:
    row = db.query(AIAgentRun).filter(AIAgentRun.run_id == run_id).first()
    now = datetime.utcnow()
    if row is None:
        row = AIAgentRun(
            run_id=run_id,
            session_id=session_id,
            user_id=user_id,
            business_id=business_id,
            status=status or AIAgentRunStatus.RUNNING,
            phase=phase or "gather_context",
            iteration=int(iteration or 0),
            needs_tools=bool(needs_tools),
            created_at=now,
            updated_at=now,
        )
        db.add(row)
    else:
        if row.session_id != session_id or row.user_id != user_id:
            raise ValueError("agent run does not belong to this session")
        row.updated_at = now

    if phase is not None:
        row.phase = str(phase)
    if iteration is not None:
        row.iteration = int(iteration)
    if needs_tools is not None:
        row.needs_tools = bool(needs_tools)
    if status is not None:
        row.status = str(status)
    if stop_reason is not None:
        row.stop_reason = str(stop_reason)
    if tools_called is not None:
        row.tools_called_json = json_dumps_safe(tools_called)
    if budget is not None:
        row.budget_json = json_dumps_safe(budget)
    if last_event_id is not None:
        row.last_event_id = max(int(row.last_event_id or 0), int(last_event_id))
    if origin_message_id is not None:
        row.origin_message_id = origin_message_id
    if extra is not None:
        row.extra_json = json_dumps_safe(extra)
    if business_id is not None:
        row.business_id = business_id
    return row


def persist_agent_run_checkpoint(
    *,
    run_id: str,
    session_id: int,
    user_id: int,
    business_id: Optional[int] = None,
    snapshot: Optional[dict[str, Any]] = None,
    status: Optional[str] = None,
    stop_reason: Optional[str] = None,
    tools_called: Optional[list[str]] = None,
    budget: Optional[dict[str, Any]] = None,
    last_event_id: Optional[int] = None,
    origin_message_id: Optional[int] = None,
    function_results: Optional[dict[str, Any]] = None,
) -> None:
    """نوشتن checkpoint در session کوتاه — شکست نباید استریم را بشکند."""
    if not run_id:
        return
    snap = snapshot or {}
    if tools_called is None and function_results is not None:
        tools_called = tools_called_from_function_results(function_results)
    try:
        from adapters.db.session import get_db_session

        with get_db_session() as db:
            upsert_agent_run(
                db,
                run_id=run_id,
                session_id=session_id,
                user_id=user_id,
                business_id=business_id,
                phase=snap.get("phase") if isinstance(snap.get("phase"), str) else None,
                iteration=snap.get("iteration") if snap.get("iteration") is not None else None,
                needs_tools=snap.get("needs_tools") if "needs_tools" in snap else None,
                status=status or snap.get("status"),
                stop_reason=stop_reason or snap.get("stop_reason"),
                tools_called=tools_called,
                budget=budget,
                last_event_id=last_event_id,
                origin_message_id=origin_message_id,
            )
            db.commit()
    except Exception as exc:
        logger.warning(
            "Failed to persist agent run checkpoint run_id=%s session=%s: %s",
            run_id,
            session_id,
            exc,
        )


def get_owned_agent_run(
    db: Session,
    *,
    run_id: str,
    session_id: int,
    user_id: int,
) -> Optional[AIAgentRun]:
    return (
        db.query(AIAgentRun)
        .filter(
            AIAgentRun.run_id == run_id,
            AIAgentRun.session_id == session_id,
            AIAgentRun.user_id == user_id,
        )
        .first()
    )


_ACTIVE_STATUSES = frozenset(
    {
        AIAgentRunStatus.RUNNING,
        AIAgentRunStatus.INTERRUPTED,
        AIAgentRunStatus.BUDGET_EXHAUSTED,
        AIAgentRunStatus.AWAITING_APPROVAL,
    }
)


def get_latest_active_run(
    db: Session,
    *,
    session_id: int,
    user_id: int,
) -> Optional[AIAgentRun]:
    return (
        db.query(AIAgentRun)
        .filter(
            AIAgentRun.session_id == session_id,
            AIAgentRun.user_id == user_id,
            AIAgentRun.status.in_(tuple(_ACTIVE_STATUSES)),
        )
        .order_by(AIAgentRun.updated_at.desc(), AIAgentRun.id.desc())
        .first()
    )


def run_to_checkpoint(row: AIAgentRun) -> dict[str, Any]:
    return {
        "run_id": row.run_id,
        "phase": row.phase,
        "iteration": row.iteration,
        "needs_tools": bool(row.needs_tools),
        "status": row.status,
        "stop_reason": row.stop_reason,
        "tools_called": _parse_json_list(row.tools_called_json),
        "last_event_id": int(row.last_event_id or 0),
        "can_continue": row.status in AIAgentRunStatus.RESUMABLE,
    }


def checkpoint_from_assistant_message(function_results: object) -> dict[str, Any] | None:
    return extract_agent_run_checkpoint(function_results)
