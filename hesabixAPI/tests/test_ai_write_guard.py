from app.services.ai.ai_write_guard import (
    build_approval_mismatch_result,
    build_approval_pause_content,
    build_approval_required_result,
    function_results_await_approval,
    is_approval_required_result,
    is_write_guard_stop_result,
    mark_function_results_awaiting_approval,
    write_call_is_approved,
)


def test_write_call_is_approved_when_arguments_match():
    approved = [{"function": "create_person", "arguments": {"name": "علی", "type": "customer"}}]

    assert write_call_is_approved(
        "create_person",
        {"type": "customer", "name": "علی"},
        approved,
    )


def test_write_call_single_card_uses_stored_arguments():
    approved = [
        {
            "function": "create_person",
            "approval_id": "abc123",
            "arguments": {"name": "علی"},
        }
    ]

    assert write_call_is_approved("create_person", {"name": "رضا"}, approved)
    from app.services.ai.ai_write_guard import resolve_approved_write

    ok, args, meta = resolve_approved_write(
        "create_person", {"name": "رضا"}, approved
    )
    assert ok is True
    assert args == {"name": "علی"}
    assert meta and meta.get("arg_diff")


def test_write_call_two_cards_still_require_exact_match():
    approved = [
        {"function": "create_person", "approval_id": "a1", "arguments": {"name": "علی"}},
        {"function": "create_person", "approval_id": "a2", "arguments": {"name": "رضا"}},
    ]
    assert not write_call_is_approved("create_person", {"name": "مینا"}, approved)
    assert write_call_is_approved("create_person", {"name": "علی"}, approved)


def test_build_approval_mismatch_result_is_structured():
    result = build_approval_mismatch_result("create_person", {"name": "رضا"})

    assert result["error"] == "APPROVAL_MISMATCH"
    assert result["status"] == "rejected"
    assert result["function"] == "create_person"


def test_is_approval_required_result():
    required = build_approval_required_result("create_person", {"name": "علی"})
    assert is_approval_required_result(required)
    assert is_write_guard_stop_result(required)
    assert required.get("approval_id")
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


class _Fn:
    def __init__(self, requires_approval: bool, is_readonly: bool = True):
        self.requires_approval = requires_approval
        self.is_readonly = is_readonly


class _Reg:
    def __init__(self, mapping):
        self._m = mapping

    def get_function(self, name):
        return self._m.get(name)


def test_is_write_function_fail_closed_unknown_with_registry():
    from app.services.ai.ai_write_guard import is_write_function, is_readonly_function

    reg = _Reg({"search_invoices": _Fn(False, True)})
    assert is_write_function("search_invoices", reg) is False
    assert is_write_function("drop_all_tables", reg) is True
    assert is_readonly_function("drop_all_tables", reg) is False


def test_extract_pending_approval_ops_from_nested_results():
    from app.services.ai.ai_write_guard import extract_pending_approval_ops

    required = build_approval_required_result("create_person", {"name": "علی"})
    ops = extract_pending_approval_ops(
        {
            "call-1": {"name": "create_person", "result": required},
            "_agent_budget": {"tokens": 1},
        }
    )
    assert len(ops) == 1
    assert ops[0]["function"] == "create_person"
    assert ops[0]["arguments"] == {"name": "علی"}
    assert ops[0].get("approval_id")


def test_extract_pending_approval_ops_dedupes_name_and_call_id():
    from app.services.ai.ai_write_guard import extract_pending_approval_ops

    required = build_approval_required_result("create_invoice", {"person_id": 7})
    ops = extract_pending_approval_ops(
        {
            "call-1": {"name": "create_invoice", "result": required},
            "create_invoice": required,
        }
    )
    assert len(ops) == 1
    assert ops[0]["function"] == "create_invoice"


def test_mismatch_does_not_stop_agent_loop():
    mismatch = build_approval_mismatch_result("create_invoice", {"person_id": 1})
    assert not is_write_guard_stop_result(mismatch)
    assert is_write_guard_stop_result(
        build_approval_required_result("create_invoice", {"person_id": 1})
    )


def test_is_write_function_honors_requires_approval_not_static_list():
    from app.services.ai.ai_write_guard import is_write_function

    reg = _Reg({"brand_new_write": _Fn(True, False)})
    assert is_write_function("brand_new_write", reg) is True
    assert is_write_function("brand_new_write") is False


def test_awaiting_approval_flag_roundtrip():
    marked = mark_function_results_awaiting_approval(
        {"create_person": {"error": "APPROVAL_REQUIRED"}},
        True,
    )
    assert function_results_await_approval(marked) is True
    cleared = mark_function_results_awaiting_approval(marked, False)
    assert function_results_await_approval(cleared) is False
    assert function_results_await_approval('{"_awaiting_approval": true}') is True

