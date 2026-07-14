"""تست‌های سازنده پیام LLM از تاریخچه چت."""
import json
import importlib.util
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace

_builder_path = Path(__file__).resolve().parents[1] / "app/services/ai/chat_message_builder.py"
_spec = importlib.util.spec_from_file_location("chat_message_builder", _builder_path)
_mod = importlib.util.module_from_spec(_spec)
assert _spec.loader is not None
_spec.loader.exec_module(_mod)

build_llm_messages_from_history = _mod.build_llm_messages_from_history
expand_strict_tool_message_pairs = _mod.expand_strict_tool_message_pairs
repair_llm_tool_messages = _mod.repair_llm_tool_messages
serialize_function_metadata = _mod.serialize_function_metadata


def test_build_with_tool_history():
    msgs = [
        SimpleNamespace(id=1, role="user", content="گزارش فروش", function_calls=None, function_results=None),
        SimpleNamespace(
            id=2,
            role="assistant",
            content="خلاصه فروش",
            function_calls=json.dumps(
                [{"name": "get_sales_report", "arguments": {"days": 7}, "id": "tc1"}]
            ),
            function_results=json.dumps({"get_sales_report": {"total": 100}}),
        ),
    ]
    built = build_llm_messages_from_history(msgs)
    assert len(built) == 3
    assert built[1]["role"] == "assistant"
    assert "tool_calls" in built[1]
    assert built[2]["role"] == "tool"
    assert built[2]["tool_call_id"] == "tc1"


def test_expand_strict_tool_message_pairs_splits_multi_tool_round():
    messages = [
        {
            "role": "assistant",
            "content": "plan",
            "tool_calls": [
                {"id": "a", "type": "function", "function": {"name": "x", "arguments": "{}"}},
                {"id": "b", "type": "function", "function": {"name": "y", "arguments": "{}"}},
            ],
        },
        {"role": "tool", "tool_call_id": "a", "content": "{}"},
        {"role": "tool", "tool_call_id": "b", "content": "{}"},
        {"role": "user", "content": "next"},
    ]
    repaired = expand_strict_tool_message_pairs(messages)
    assert repaired[0]["role"] == "assistant"
    assert len(repaired[0]["tool_calls"]) == 1
    assert repaired[1]["role"] == "tool"
    assert repaired[1]["tool_call_id"] == "a"
    assert repaired[2]["role"] == "assistant"
    assert len(repaired[2]["tool_calls"]) == 1
    assert repaired[3]["role"] == "tool"
    assert repaired[3]["tool_call_id"] == "b"
    assert repaired[4]["role"] == "user"


def test_repair_llm_tool_messages_drops_leading_orphan_tool():
    messages = [
        {"role": "tool", "tool_call_id": "orphan", "content": "{}"},
        {"role": "user", "content": "hi"},
    ]
    repaired = repair_llm_tool_messages(messages)
    assert repaired == [{"role": "user", "content": "hi"}]


def test_build_with_empty_function_calls_dict_falls_back_to_assistant():
    msgs = [
        SimpleNamespace(
            id=2,
            role="assistant",
            content="پاسخ",
            function_calls=json.dumps({"calls": []}),
            function_results=None,
        ),
    ]
    built = build_llm_messages_from_history(msgs)
    assert built == [{"role": "assistant", "content": "پاسخ"}]


def test_build_with_tool_history_prefers_tool_call_id_result():
    msgs = [
        SimpleNamespace(
            id=2,
            role="assistant",
            content="",
            function_calls=json.dumps(
                [
                    {"name": "search_persons", "arguments": {"q": "علی"}, "id": "call_a"},
                    {"name": "search_persons", "arguments": {"q": "رضا"}, "id": "call_b"},
                ]
            ),
            function_results=json.dumps(
                {
                    "call_a": {"name": "search_persons", "result": {"items": ["علی"]}},
                    "call_b": {"name": "search_persons", "result": {"items": ["رضا"]}},
                    "search_persons": {"items": ["fallback"]},
                },
                ensure_ascii=False,
            ),
        ),
    ]
    built = build_llm_messages_from_history(msgs)

    assert built[0]["role"] == "assistant"
    assert json.loads(built[1]["content"])["items"] == ["علی"]
    assert built[2]["role"] == "assistant"
    assert json.loads(built[3]["content"])["items"] == ["رضا"]


def test_serialize_metadata():
    fc, fr = serialize_function_metadata([{"name": "x"}], {"x": 1})
    assert fc is not None and fr is not None


def test_serialize_metadata_datetime():
    dt = datetime(2026, 5, 26, 17, 15, 20)
    fc, fr = serialize_function_metadata(
        [{"name": "search_invoices"}],
        {"search_invoices": {"items": [{"document_date": dt}]}},
    )
    assert fr is not None
    parsed = json.loads(fr)
    assert parsed["search_invoices"]["items"][0]["document_date"] == dt.isoformat()
