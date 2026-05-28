from app.services.ai.ai_write_guard import (
    build_approval_mismatch_result,
    build_approval_pause_content,
    build_approval_required_result,
    is_approval_required_result,
    is_write_guard_stop_result,
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


def test_is_approval_required_result():
    required = build_approval_required_result("create_person", {"name": "علی"})
    assert is_approval_required_result(required)
    assert is_write_guard_stop_result(required)
    assert not is_approval_required_result({"ok": True})


def test_build_approval_pause_content_single_operation():
    calls = [{"name": "create_person"}]
    results = build_approval_required_result("create_person", {"name": "علی"})

    text = build_approval_pause_content(
        calls,
        lambda c: results if c["name"] == "create_person" else {},
    )

    assert "create_person" not in text  # label فارسی
    assert "تأیید" in text
