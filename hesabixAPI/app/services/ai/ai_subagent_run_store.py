"""ذخیره و بازیابی زیر-ایجنت در جدول ai_subagent_runs (CHAT-12)."""
from __future__ import annotations

import json
import logging
from datetime import datetime
from typing import Any, Optional

from sqlalchemy.orm import Session

from adapters.db.models.ai_subagent_run import AISubagentRun, AISubagentRunStatus
from app.core.json_safe import json_dumps_safe

logger = logging.getLogger(__name__)

_RESULT_JSON_MAX = 50_000


def _error_from_result(result: Optional[dict[str, Any]]) -> Optional[str]:
    if not isinstance(result, dict):
        return None
    err = result.get("error")
    if err is None:
        return None
    text = str(err).strip()
    return text[:128] if text else None


def upsert_subagent_run(
    db: Session,
    *,
    subagent_id: str,
    session_id: int,
    business_id: Optional[int] = None,
    goal: str = "",
    status: Optional[str] = None,
    error: Optional[str] = None,
    result: Optional[dict[str, Any]] = None,
) -> AISubagentRun:
    row = (
        db.query(AISubagentRun)
        .filter(AISubagentRun.subagent_id == subagent_id)
        .first()
    )
    now = datetime.utcnow()
    status_val = status or AISubagentRunStatus.RUNNING
    if status_val not in AISubagentRunStatus.ALL:
        status_val = AISubagentRunStatus.FAILED
    err = error if error is not None else _error_from_result(result)
    result_json = None
    if result is not None:
        dumped = json_dumps_safe(result)
        result_json = dumped[:_RESULT_JSON_MAX]
    if row is None:
        row = AISubagentRun(
            subagent_id=subagent_id,
            session_id=session_id,
            business_id=business_id,
            goal=goal or "",
            status=status_val,
            error=err,
            result_json=result_json,
            created_at=now,
            updated_at=now,
        )
        db.add(row)
        return row
    row.session_id = session_id
    if business_id is not None:
        row.business_id = business_id
    if goal:
        row.goal = goal
    row.status = status_val
    row.error = err
    if result_json is not None:
        row.result_json = result_json
    row.updated_at = now
    return row


def persist_subagent_run(
    *,
    subagent_id: str,
    session_id: Optional[int],
    business_id: Optional[int] = None,
    goal: str = "",
    status: Optional[str] = None,
    result: Optional[dict[str, Any]] = None,
) -> None:
    """نوشتن در session کوتاه — شکست نباید حلقهٔ agent را بشکند."""
    if not subagent_id or session_id is None:
        return
    try:
        from adapters.db.session import get_db_session

        with get_db_session() as db:
            upsert_subagent_run(
                db,
                subagent_id=subagent_id,
                session_id=int(session_id),
                business_id=business_id,
                goal=goal,
                status=status,
                result=result,
            )
            db.commit()
    except Exception as exc:
        logger.warning(
            "Failed to persist subagent %s session=%s: %s",
            subagent_id,
            session_id,
            exc,
        )


def mark_stale_running_interrupted(
    db: Session, *, session_id: int, live_ids: set[str]
) -> int:
    """فرزند running که روی این فرآیند نیست بعد از ری‌استارت interrupted است."""
    rows = (
        db.query(AISubagentRun)
        .filter(
            AISubagentRun.session_id == session_id,
            AISubagentRun.status == AISubagentRunStatus.RUNNING,
        )
        .all()
    )
    n = 0
    now = datetime.utcnow()
    for row in rows:
        if row.subagent_id in live_ids:
            continue
        row.status = AISubagentRunStatus.INTERRUPTED
        row.error = row.error or "SUBAGENT_INTERRUPTED"
        row.updated_at = now
        n += 1
    if n:
        db.commit()
    return n


def row_to_ui_item(row: AISubagentRun) -> dict[str, Any]:
    return {
        "subagent_id": row.subagent_id,
        "goal": row.goal or "",
        "status": row.status,
        "error": row.error,
    }


def list_session_subagent_rows(
    db: Session, session_id: int
) -> list[dict[str, Any]]:
    rows = (
        db.query(AISubagentRun)
        .filter(AISubagentRun.session_id == session_id)
        .order_by(AISubagentRun.created_at.asc(), AISubagentRun.id.asc())
        .all()
    )
    return [row_to_ui_item(row) for row in rows]


def parse_result_json(raw: Optional[str]) -> Optional[dict[str, Any]]:
    if not raw:
        return None
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, dict) else None
