"""تست‌های واحد ai_provider.py — فیلتر tool_call بدون نام و tool_choice (Phase 2/3)."""
from __future__ import annotations

from types import SimpleNamespace

from app.services.ai.ai_provider import (
    OpenAIProvider,
    _anthropic_blocks_to_openai_result,
)


def test_anthropic_blocks_filters_empty_name_tool_use():
    """tool_use بدون نام معتبر باید نادیده گرفته شود (Phase 3)."""
    blocks = [
        SimpleNamespace(type="text", text="سلام"),
        SimpleNamespace(type="tool_use", id="call_1", name="", input={}),
        SimpleNamespace(type="tool_use", id="call_2", name="   ", input={}),
        SimpleNamespace(
            type="tool_use", id="call_3", name="search_invoices", input={"q": "x"}
        ),
    ]
    content, function_calls = _anthropic_blocks_to_openai_result(blocks)
    assert content == "سلام"
    assert function_calls is not None
    assert len(function_calls) == 1
    assert function_calls[0]["name"] == "search_invoices"


def test_anthropic_blocks_no_tool_use_returns_none_calls():
    blocks = [SimpleNamespace(type="text", text="فقط متن")]
    content, function_calls = _anthropic_blocks_to_openai_result(blocks)
    assert content == "فقط متن"
    assert function_calls is None


def test_anthropic_blocks_all_empty_names_returns_none():
    blocks = [
        SimpleNamespace(type="tool_use", id="call_1", name=None, input={}),
    ]
    content, function_calls = _anthropic_blocks_to_openai_result(blocks)
    assert function_calls is None


def _make_openai_provider() -> OpenAIProvider:
    return OpenAIProvider(api_key="test-key")


def test_openai_build_request_kwargs_applies_tool_choice_when_tools_present():
    provider = _make_openai_provider()
    tools = [{"type": "function", "function": {"name": "search_invoices"}}]
    kwargs = provider._build_request_kwargs(
        messages=[{"role": "user", "content": "سلام"}],
        model="gpt-4o",
        max_tokens=1000,
        temperature=0.2,
        tools=tools,
        reasoning_effort=None,
        provider_extra=None,
        tool_choice="required",
    )
    assert kwargs.get("tool_choice") == "required"


def test_openai_build_request_kwargs_ignores_tool_choice_without_tools():
    """اگر tools خالی باشد، tool_choice نباید ارسال شود (وگرنه provider خطا می‌دهد)."""
    provider = _make_openai_provider()
    kwargs = provider._build_request_kwargs(
        messages=[{"role": "user", "content": "سلام"}],
        model="gpt-4o",
        max_tokens=1000,
        temperature=0.2,
        tools=None,
        reasoning_effort=None,
        provider_extra=None,
        tool_choice="required",
    )
    assert "tool_choice" not in kwargs


def test_openai_build_request_kwargs_no_tool_choice_by_default():
    provider = _make_openai_provider()
    tools = [{"type": "function", "function": {"name": "search_invoices"}}]
    kwargs = provider._build_request_kwargs(
        messages=[{"role": "user", "content": "سلام"}],
        model="gpt-4o",
        max_tokens=1000,
        temperature=0.2,
        tools=tools,
        reasoning_effort=None,
        provider_extra=None,
    )
    assert "tool_choice" not in kwargs
