"""تست سرویس برنامهٔ کاری جلسهٔ چت AI."""
from __future__ import annotations

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from adapters.db.models.ai_session_todo import AISessionTodo, AISessionTodoStatus
from adapters.db.session import Base
from app.services.ai.ai_session_todo_events import drain_session_todo_sse, reset_session_todo_sse_buffer
from app.services.ai.ai_session_todo_service import (
    create_session_plan,
    format_session_todos_for_prompt,
    list_session_todos,
    should_expose_session_plan_tools,
    update_session_todo,
)


@pytest.fixture()
def db() -> Session:
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine, tables=[AISessionTodo.__table__])
    factory = sessionmaker(bind=engine)
    session = factory()
    try:
        yield session
    finally:
        session.close()


def test_create_and_update_session_plan_emits_sse(db: Session) -> None:
    reset_session_todo_sse_buffer()
    rows = create_session_plan(
        db,
        10,
        [
            {"title": "جمع‌آوری داده", "order": 0},
            {"title": "تحلیل", "order": 1},
        ],
        plan_title="گزارش فروش",
    )
    db.commit()
    assert len(rows) == 2
    assert rows[0].status == AISessionTodoStatus.PENDING

    events = drain_session_todo_sse()
    assert len(events) == 1
    assert events[0]["event"] == "session_todo_snapshot"
    assert events[0]["summary"]["total"] == 2

    todo_id = rows[0].public_id
    update_session_todo(db, 10, todo_id=todo_id, status="in_progress")
    db.commit()
    updated = list_session_todos(db, 10)
    assert updated[0].status == AISessionTodoStatus.IN_PROGRESS
    assert updated[0].started_at is not None

    update_session_todo(db, 10, todo_id=todo_id, status="done")
    db.commit()
    done_rows = list_session_todos(db, 10)
    assert done_rows[0].status == AISessionTodoStatus.DONE
    assert done_rows[0].completed_at is not None


def test_format_session_todos_for_prompt(db: Session) -> None:
    create_session_plan(
        db,
        10,
        [{"title": "مرحله اول"}, {"title": "مرحله دوم", "status": "in_progress"}],
    )
    db.commit()
    text = format_session_todos_for_prompt(db, 10)
    assert "برنامهٔ کاری جاری" in text
    assert "مرحله اول" in text


def test_should_expose_session_plan_tools_complex_query() -> None:
    assert should_expose_session_plan_tools(
        "گزارش فروش ۶ ماه را با موجودی انبار مقایسه کن و لیست بدهکاران را هم بساز"
    )
    assert not should_expose_session_plan_tools("سلام")


def test_replace_existing_plan_clears_open_items(db: Session) -> None:
    create_session_plan(db, 10, [{"title": "قدیمی"}])
    db.commit()
    create_session_plan(
        db,
        10,
        [{"title": "جدید"}],
        replace_existing=True,
    )
    db.commit()
    rows = list_session_todos(db, 10)
    assert len(rows) == 1
    assert rows[0].title == "جدید"
