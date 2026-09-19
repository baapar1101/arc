"""تست وضعیت اجرای agent و checkpoint (Phase 2)."""
from __future__ import annotations

from app.services.ai.ai_agent_run import (
    AGENT_RUN_PHASE_AGENT_LOOP,
    AGENT_RUN_PHASE_DONE,
    AgentRunState,
    build_resume_continue_prompt,
    extract_agent_run_checkpoint,
    new_agent_run_id,
)


def test_new_run_id_is_short_hex():
    rid = new_agent_run_id()
    assert len(rid) == 16
    assert all(c in "0123456789abcdef" for c in rid)


def test_agent_run_snapshot_and_phase():
    run = AgentRunState(needs_tools=True)
    run.iteration = 2
    run.set_phase(AGENT_RUN_PHASE_AGENT_LOOP)
    snap = run.snapshot()
    assert snap["needs_tools"] is True
    assert snap["iteration"] == 2
    assert snap["phase"] == AGENT_RUN_PHASE_AGENT_LOOP
    run.set_phase(AGENT_RUN_PHASE_DONE)
    assert run.phase == AGENT_RUN_PHASE_DONE


def test_extract_checkpoint_from_function_results():
    fr = {
        "_agent_run": {
            "run_id": "abc123def4567890",
            "phase": "done",
            "iteration": 3,
            "needs_tools": True,
        }
    }
    cp = extract_agent_run_checkpoint(fr)
    assert cp is not None
    assert cp["run_id"] == "abc123def4567890"
    assert cp["iteration"] == 3
    assert cp["needs_tools"] is True


def test_extract_checkpoint_missing():
    assert extract_agent_run_checkpoint(None) is None
    assert extract_agent_run_checkpoint({}) is None
    assert extract_agent_run_checkpoint({"_agent_run": {}}) is None


def test_resume_prompt_includes_run_id():
    prompt = build_resume_continue_prompt(
        {"run_id": "deadbeefcafebabe", "iteration": 4}
    )
    assert "deadbeefcafebabe" in prompt
    assert "4" in prompt
    assert "[agent_resume]" in prompt


def test_resume_prompt_lists_prior_tools():
    prompt = build_resume_continue_prompt(
        {"run_id": "deadbeefcafebabe", "iteration": 2, "stop_reason": "max_iterations"},
        tools_called=["search_invoices", "get_sales_report"],
    )
    assert "search_invoices" in prompt
    assert "max_iterations" in prompt


def test_snapshot_can_continue_on_budget_stop():
    from app.services.ai.ai_agent_run import (
        AGENT_RUN_STATUS_BUDGET_EXHAUSTED,
        is_resumable_stop_reason,
        status_for_stop,
    )

    assert is_resumable_stop_reason("max_iterations") is True
    assert is_resumable_stop_reason("disconnect") is True
    assert is_resumable_stop_reason(None) is False
    assert status_for_stop(stop_reason="token_budget") == AGENT_RUN_STATUS_BUDGET_EXHAUSTED
    run = AgentRunState(status=AGENT_RUN_STATUS_BUDGET_EXHAUSTED, stop_reason="wall_clock")
    assert run.snapshot()["can_continue"] is True
