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

    assert json.loads(built[1]["content"])["items"] == ["علی"]
    assert json.loads(built[2]["content"])["items"] == ["رضا"]


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
