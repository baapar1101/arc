from app.services.ai.ai_write_guard import (
    build_approval_mismatch_result,
    write_call_is_approved,
)


def test_write_call_is_approved_when_arguments_match():
    approved = [{"function": "create_person", "arguments": {"name": "علی", "type": "customer"}}]

    assert write_call_is_approved(
        "create_person",
        {"type": "customer", "name": "علی"},
        approved,
    )


def test_write_call_rejects_changed_arguments():
    approved = [{"function": "create_person", "arguments": {"name": "علی"}}]

    assert not write_call_is_approved("create_person", {"name": "رضا"}, approved)


def test_build_approval_mismatch_result_is_structured():
    result = build_approval_mismatch_result("create_person", {"name": "رضا"})

    assert result["error"] == "APPROVAL_MISMATCH"
    assert result["status"] == "rejected"
    assert result["function"] == "create_person"
