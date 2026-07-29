"""تست اتصال AgentGoalTracker به برنامهٔ کاری جلسه."""
from __future__ import annotations

from app.services.ai.ai_goal_assessment import AgentGoalTracker
from app.services.ai.ai_session_todo_service import SessionTodoGoalState


def _lookup(results, call):
    name = call.get("name")
    val = results.get(name)
    if isinstance(val, dict) and "result" in val:
        return val["result"]
    return val


def test_goal_reached_when_all_session_todos_complete() -> None:
    tracker = AgentGoalTracker()
    state = SessionTodoGoalState(
        has_plan=True,
        total=3,
        completed=3,
        in_progress=0,
        pending=0,
        error_count=0,
        all_complete=True,
        has_open=False,
    )
    assessment = tracker.assess_after_tool_round(
        [{"name": "get_sales_report", "arguments": {}}],
        {
            "get_sales_report": {
                "name": "get_sales_report",
                "result": {"items": [1, 2, 3]},
            }
        },
        _lookup,
        session_todo_state=state,
    )
    assert assessment.goal_reached is True
    assert assessment.should_continue is False


def test_goal_not_reached_with_open_session_todos() -> None:
    tracker = AgentGoalTracker()
    state = SessionTodoGoalState(
        has_plan=True,
        total=4,
        completed=1,
        in_progress=1,
        pending=2,
        error_count=0,
        all_complete=False,
        has_open=True,
        open_titles=("تحلیل فروش", "گزارش نهایی"),
    )
    assessment = tracker.assess_after_tool_round(
        [{"name": "search_invoices", "arguments": {}}],
        {
            "search_invoices": {
                "name": "search_invoices",
                "result": {"items": [1, 2]},
            }
        },
        _lookup,
        session_todo_state=state,
    )
    assert assessment.goal_reached is False
    assert assessment.should_continue is True
    assert "برنامهٔ کاری" in (assessment.reason_fa or "")


def test_continue_context_includes_open_todos() -> None:
    tracker = AgentGoalTracker()
    state = SessionTodoGoalState(
        has_plan=True,
        total=2,
        completed=0,
        in_progress=1,
        pending=1,
        error_count=0,
        all_complete=False,
        has_open=True,
        open_titles=("مرحله اول",),
    )
    tracker.assess_after_tool_round(
        [{"name": "list_session_todos", "arguments": {}}],
        {
            "list_session_todos": {
                "name": "list_session_todos",
                "result": {"items": [{"title": "مرحله اول"}]},
            }
        },
        _lookup,
        session_todo_state=state,
    )
    ctx = tracker.continue_context_for_llm()
    assert ctx is not None
    assert "برنامهٔ کاری" in ctx
    assert "مرحله اول" in ctx
