"""
مدیریت برنامهٔ کاری موقت agent در جلسهٔ چت.
"""
from __future__ import annotations

import json
import re
import uuid
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import and_, select
from sqlalchemy.orm import Session

from adapters.db.models.ai_session_todo import AISessionTodo, AISessionTodoStatus
from app.services.ai.ai_constants import PROVIDERS_WITH_FORCED_TOOLS
from app.services.ai.ai_session_todo_events import emit_session_todo_sse
from app.services.ai.ai_tool_intent import estimate_query_complexity

AGENT_TODOS_STORAGE_KEY = "_agent_todos"

MAX_TODOS_PER_SESSION = 20
MAX_TODO_TITLE_CHARS = 300
MAX_TODO_DESCRIPTION_CHARS = 2000

_SESSION_PLAN_KEYWORDS = re.compile(
    r"(مرحله|گام|قدم|سناریو|چند\s*مرحله|چندمرحله|گزارش\s*جامع|تحلیل\s*کامل|"
    r"مقایسه|ترکیب|پشت\s*سر\s*هم|یکی\s*یکی|گام\s*به\s*گام|"
    r"step\s*by\s*step|multi[\s-]?step|workflow|checklist|todo|plan)",
    re.IGNORECASE,
)

SESSION_TODO_TOOL_NAMES = frozenset({
    "create_session_plan",
    "list_session_todos",
    "update_session_todo",
})


def new_todo_public_id() -> str:
    return uuid.uuid4().hex[:12]


def _normalize_status(value: Optional[str]) -> str:
    status = (value or AISessionTodoStatus.PENDING).strip().lower()
    if status not in AISessionTodoStatus.ALL:
        raise ValueError(f"وضعیت نامعتبر: {value}")
    return status


def _clamp_text(value: Optional[str], max_len: int) -> str:
    text = (value or "").strip()
    if not text:
        raise ValueError("متن خالی مجاز نیست")
    if len(text) > max_len:
        return text[: max_len - 1] + "…"
    return text


def todo_to_dict(row: AISessionTodo) -> Dict[str, Any]:
    return {
        "id": row.public_id,
        "title": row.title,
        "description": row.description,
        "status": row.status,
        "order": row.sort_order,
        "linked_tool": row.linked_tool,
        "error_message": row.error_message,
        "started_at": row.started_at.isoformat() if row.started_at else None,
        "completed_at": row.completed_at.isoformat() if row.completed_at else None,
        "updated_at": row.updated_at.isoformat() if row.updated_at else None,
    }


def list_session_todos(
    db: Session,
    session_id: int,
    *,
    include_completed: bool = True,
) -> List[AISessionTodo]:
    stmt = (
        select(AISessionTodo)
        .where(AISessionTodo.session_id == session_id)
        .order_by(AISessionTodo.sort_order.asc(), AISessionTodo.id.asc())
    )
    if not include_completed:
        stmt = stmt.where(
            AISessionTodo.status.in_(
                (AISessionTodoStatus.PENDING, AISessionTodoStatus.IN_PROGRESS)
            )
        )
    return list(db.scalars(stmt).all())


def session_has_open_todos(db: Session, session_id: int) -> bool:
    row = db.scalar(
        select(AISessionTodo.id)
        .where(
            and_(
                AISessionTodo.session_id == session_id,
                AISessionTodo.status.in_(
                    (AISessionTodoStatus.PENDING, AISessionTodoStatus.IN_PROGRESS)
                ),
            )
        )
        .limit(1)
    )
    return row is not None


def todos_summary(todos: List[AISessionTodo]) -> Dict[str, int]:
    total = len(todos)
    done = sum(
        1
        for t in todos
        if t.status in (AISessionTodoStatus.DONE, AISessionTodoStatus.SKIPPED)
    )
    in_progress = sum(1 for t in todos if t.status == AISessionTodoStatus.IN_PROGRESS)
    return {
        "total": total,
        "completed": done,
        "in_progress": in_progress,
        "pending": max(0, total - done - in_progress),
    }


@dataclass(frozen=True)
class SessionTodoGoalState:
    """وضعیت برنامهٔ کاری برای ارزیابی هدف agent."""

    has_plan: bool
    total: int
    completed: int
    in_progress: int
    pending: int
    error_count: int
    all_complete: bool
    has_open: bool
    open_titles: tuple[str, ...] = ()

    @property
    def progress_label_fa(self) -> str:
        return f"{self.completed} از {self.total} مرحله"


def get_session_todo_goal_state(db: Session, session_id: int) -> SessionTodoGoalState:
    rows = list_session_todos(db, session_id, include_completed=True)
    if not rows:
        return SessionTodoGoalState(
            has_plan=False,
            total=0,
            completed=0,
            in_progress=0,
            pending=0,
            error_count=0,
            all_complete=False,
            has_open=False,
        )
    summary = todos_summary(rows)
    error_count = sum(1 for r in rows if r.status == AISessionTodoStatus.ERROR)
    open_rows = [
        r
        for r in rows
        if r.status
        in (AISessionTodoStatus.PENDING, AISessionTodoStatus.IN_PROGRESS, AISessionTodoStatus.ERROR)
    ]
    all_complete = summary["total"] > 0 and summary["completed"] >= summary["total"]
    return SessionTodoGoalState(
        has_plan=True,
        total=summary["total"],
        completed=summary["completed"],
        in_progress=summary["in_progress"],
        pending=summary["pending"],
        error_count=error_count,
        all_complete=all_complete,
        has_open=bool(open_rows),
        open_titles=tuple(r.title for r in open_rows[:6]),
    )


def format_open_todos_for_agent_context(state: SessionTodoGoalState) -> str:
    if not state.has_plan or not state.has_open:
        return ""
    lines = [
        "[ادامهٔ برنامهٔ کاری]",
        f"پیشرفت: {state.progress_label_fa}",
        "مراحل باز:",
    ]
    for title in state.open_titles:
        lines.append(f"- {title}")
    open_count = state.pending + state.in_progress + state.error_count
    if open_count > len(state.open_titles):
        lines.append(f"- … و {open_count - len(state.open_titles)} مورد دیگر")
    lines.append(
        "قبل از پاسخ نهایی، مرحلهٔ جاری را in_progress و پس از اتمام done کن."
    )
    return "\n".join(lines)


def build_todo_snapshot_payload(
    todos: List[AISessionTodo],
    *,
    plan_title: Optional[str] = None,
) -> Dict[str, Any]:
    summary = todos_summary(todos)
    payload: Dict[str, Any] = {
        "event": "session_todo_snapshot",
        "items": [todo_to_dict(t) for t in todos],
        "summary": summary,
    }
    if plan_title:
        payload["plan_title"] = plan_title
    return payload


def emit_todo_snapshot(
    todos: List[AISessionTodo],
    *,
    plan_title: Optional[str] = None,
) -> None:
    emit_session_todo_sse(build_todo_snapshot_payload(todos, plan_title=plan_title))


def create_session_plan(
    db: Session,
    session_id: int,
    items: List[Dict[str, Any]],
    *,
    origin_message_id: Optional[int] = None,
    plan_title: Optional[str] = None,
    replace_existing: bool = True,
) -> List[AISessionTodo]:
    if not items:
        raise ValueError("حداقل یک آیتم برای برنامه لازم است")
    if len(items) > MAX_TODOS_PER_SESSION:
        raise ValueError(f"حداکثر {MAX_TODOS_PER_SESSION} آیتم در هر برنامه مجاز است")

    if replace_existing:
        existing = list_session_todos(db, session_id)
        for row in existing:
            if row.status in (AISessionTodoStatus.PENDING, AISessionTodoStatus.IN_PROGRESS):
                db.delete(row)

    created: List[AISessionTodo] = []
    now = datetime.utcnow()
    for idx, raw in enumerate(items):
        if not isinstance(raw, dict):
            raise ValueError("هر آیتم باید شیء باشد")
        title = _clamp_text(raw.get("title"), MAX_TODO_TITLE_CHARS)
        description = (raw.get("description") or "").strip() or None
        if description and len(description) > MAX_TODO_DESCRIPTION_CHARS:
            description = description[: MAX_TODO_DESCRIPTION_CHARS - 1] + "…"
        status = _normalize_status(raw.get("status") or AISessionTodoStatus.PENDING)
        linked_tool = (raw.get("linked_tool") or "").strip() or None
        row = AISessionTodo(
            public_id=new_todo_public_id(),
            session_id=session_id,
            origin_message_id=origin_message_id,
            title=title,
            description=description,
            status=status,
            sort_order=int(raw.get("order") if raw.get("order") is not None else idx),
            linked_tool=linked_tool,
            started_at=now if status == AISessionTodoStatus.IN_PROGRESS else None,
            completed_at=now
            if status in (AISessionTodoStatus.DONE, AISessionTodoStatus.SKIPPED)
            else None,
        )
        db.add(row)
        created.append(row)

    db.flush()
    all_rows = list_session_todos(db, session_id)
    emit_todo_snapshot(all_rows, plan_title=plan_title)
    return all_rows


def apply_user_todo_status(
    db: Session,
    session_id: int,
    todo_id: str,
    status: str,
) -> List[AISessionTodo]:
    """رد یا تأیید آیتم باز توسط کاربر — فقط skipped/done از pending/in_progress."""
    wanted = _normalize_status(status)
    if wanted not in (AISessionTodoStatus.SKIPPED, AISessionTodoStatus.DONE):
        raise ValueError("فقط رد کردن یا انجام‌شده برای تصمیم کاربر مجاز است")
    public_id = (todo_id or "").strip()
    if not public_id:
        raise ValueError("شناسه آیتم الزامی است")
    row = db.scalar(
        select(AISessionTodo).where(
            and_(
                AISessionTodo.session_id == session_id,
                AISessionTodo.public_id == public_id,
            )
        )
    )
    if row is None:
        raise ValueError("آیتم برنامه یافت نشد")
    if row.status not in (
        AISessionTodoStatus.PENDING,
        AISessionTodoStatus.IN_PROGRESS,
    ):
        raise ValueError("فقط آیتم باز را می‌توان رد یا تأیید کرد")
    update_session_todo(db, session_id, todo_id=public_id, status=wanted)
    return list_session_todos(db, session_id)


def update_session_todo(
    db: Session,
    session_id: int,
    *,
    todo_id: str,
    title: Optional[str] = None,
    description: Optional[str] = None,
    status: Optional[str] = None,
    order: Optional[int] = None,
    linked_tool: Optional[str] = None,
    error_message: Optional[str] = None,
) -> AISessionTodo:
    public_id = (todo_id or "").strip()
    if not public_id:
        raise ValueError("شناسه آیتم الزامی است")

    row = db.scalar(
        select(AISessionTodo).where(
            and_(
                AISessionTodo.session_id == session_id,
                AISessionTodo.public_id == public_id,
            )
        )
    )
    if row is None:
        raise ValueError("آیتم برنامه یافت نشد")

    now = datetime.utcnow()
    if title is not None:
        row.title = _clamp_text(title, MAX_TODO_TITLE_CHARS)
    if description is not None:
        desc = description.strip() or None
        if desc and len(desc) > MAX_TODO_DESCRIPTION_CHARS:
            desc = desc[: MAX_TODO_DESCRIPTION_CHARS - 1] + "…"
        row.description = desc
    if order is not None:
        row.sort_order = int(order)
    if linked_tool is not None:
        row.linked_tool = linked_tool.strip() or None
    if error_message is not None:
        row.error_message = error_message.strip() or None

    if status is not None:
        new_status = _normalize_status(status)
        prev_status = row.status
        row.status = new_status
        if new_status == AISessionTodoStatus.IN_PROGRESS and prev_status != new_status:
            row.started_at = row.started_at or now
        if new_status in (
            AISessionTodoStatus.DONE,
            AISessionTodoStatus.SKIPPED,
            AISessionTodoStatus.ERROR,
        ):
            row.completed_at = now

    row.updated_at = now
    db.flush()

    all_rows = list_session_todos(db, session_id)
    emit_todo_snapshot(all_rows)
    return row


def format_session_todos_for_prompt(db: Session, session_id: int) -> str:
    todos = list_session_todos(db, session_id, include_completed=False)
    if not todos:
        open_all = list_session_todos(db, session_id)
        active = [
            t
            for t in open_all
            if t.status in (AISessionTodoStatus.PENDING, AISessionTodoStatus.IN_PROGRESS)
        ]
        if not active:
            return ""
        todos = active

    lines = [
        "\n\n[برنامهٔ کاری جاری این گفت‌وگو]",
        "این لیست را با ابزار update_session_todo به‌روز نگه دار.",
    ]
    summary = todos_summary(list_session_todos(db, session_id))
    lines.append(
        f"پیشرفت: {summary['completed']}/{summary['total']} تکمیل‌شده"
    )
    for row in todos:
        marker = {
            AISessionTodoStatus.PENDING: "○",
            AISessionTodoStatus.IN_PROGRESS: "◉",
            AISessionTodoStatus.DONE: "✓",
            AISessionTodoStatus.SKIPPED: "—",
            AISessionTodoStatus.ERROR: "✗",
        }.get(row.status, "○")
        line = f"{marker} [{row.public_id}] {row.title}"
        if row.linked_tool:
            line += f" (ابزار: {row.linked_tool})"
        lines.append(line)
    return "\n".join(lines)


def should_expose_session_plan_tools(
    user_query: Optional[str],
    *,
    session_id: Optional[int] = None,
    db: Optional[Session] = None,
) -> bool:
    q = (user_query or "").strip()
    if not q:
        return False

    complexity = estimate_query_complexity(q)
    if complexity in ("medium", "complex"):
        return True
    if _SESSION_PLAN_KEYWORDS.search(q):
        return True
    if session_id and db is not None and session_has_open_todos(db, session_id):
        return True
    return False


def session_plan_tools_prompt_block(*, require_first: bool = False) -> str:
    if require_first:
        return (
            "\n\n[ابزار برنامهٔ کاری جلسه — الزامی]\n"
            "این سوال چندمرحله‌ای است. اگر برنامهٔ باز در بالا نیست، "
            "اولین فراخوانی ابزار باید create_session_plan باشد "
            "(۳ تا ۸ آیتم کوتاه و عملیاتی با linked_tool در صورت امکان). "
            "سپس ابزارهای داده را طبق همان برنامه صدا بزن.\n"
            "قبل از شروع هر آیتم وضعیت را in_progress و پس از اتمام done کن.\n"
            "حداکثر ۲۰ آیتم."
        )
    return (
        "\n\n[ابزار برنامهٔ کاری جلسه]\n"
        "برای سناریوهای چندمرحله‌ای (بیش از ۲ ابزار، گزارش ترکیبی، تحلیل زنجیره‌ای) "
        "می‌توانی از create_session_plan استفاده کنی.\n"
        "قبل از شروع هر آیتم وضعیت را in_progress و پس از اتمام done کن.\n"
        "برای سوالات ساده یک‌مرحله‌ای نیازی به ساخت برنامه نیست.\n"
        "حداکثر ۲۰ آیتم؛ عنوان‌ها کوتاه و عملیاتی باشند."
    )


def required_plan_tool_choice(
    *,
    complexity: str,
    iteration: int,
    has_open_todos: bool,
    plan_tool_available: bool,
    provider_type: Optional[str],
) -> Optional[Dict[str, Any]]:
    """نوبت اول سوال complex بدون برنامهٔ باز: مدل را به create_session_plan مجبور کن."""
    if (
        complexity == "complex"
        and iteration == 1
        and not has_open_todos
        and plan_tool_available
        and (provider_type or "").strip().lower() in PROVIDERS_WITH_FORCED_TOOLS
    ):
        return {
            "type": "function",
            "function": {"name": "create_session_plan"},
        }
    return None


def tools_include_name(tools: Optional[List[Dict[str, Any]]], name: str) -> bool:
    if not tools or not name:
        return False
    for item in tools:
        fn = (item.get("function") or {}).get("name") if isinstance(item, dict) else None
        if fn == name:
            return True
    return False


def merge_todos_into_function_results(
    function_results: Optional[Dict[str, Any]],
    todos: List[Dict[str, Any]],
    *,
    summary: Optional[Dict[str, int]] = None,
) -> Dict[str, Any]:
    merged = dict(function_results or {})
    if todos:
        merged[AGENT_TODOS_STORAGE_KEY] = {
            "items": todos,
            "summary": summary or {},
        }
    return merged


def todos_dicts_from_rows(rows: List[AISessionTodo]) -> List[Dict[str, Any]]:
    return [todo_to_dict(r) for r in rows]


def parse_plan_items_arg(raw_items: Any) -> List[Dict[str, Any]]:
    if isinstance(raw_items, list):
        return [dict(x) for x in raw_items if isinstance(x, dict)]
    if isinstance(raw_items, str):
        try:
            parsed = json.loads(raw_items)
        except json.JSONDecodeError as exc:
            raise ValueError("فرمت items نامعتبر است") from exc
        if isinstance(parsed, list):
            return [dict(x) for x in parsed if isinstance(x, dict)]
    raise ValueError("پارامتر items باید آرایه‌ای از اشیاء باشد")
