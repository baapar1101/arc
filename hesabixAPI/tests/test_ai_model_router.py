"""تست مسیریابی مدل جدا از God Object (ARC-01)."""
from __future__ import annotations

from app.services.ai.ai_constants import AI_OPERATION_CHAT, AI_OPERATION_TITLE
from app.services.ai.ai_model_router import AIModelRouterMixin


class _RouterHost(AIModelRouterMixin):
    def __init__(self) -> None:
        self.db = None
        self.subscription = None
        self.config = None
        self.business_id = 1
        self.ctx = None
        self._request_model_code = None
        self._routing_context = None


def test_routing_context_merges_overrides() -> None:
    host = _RouterHost()
    host.set_routing_context(
        operation=AI_OPERATION_TITLE,
        user_query="سلام",
        needs_tools=True,
    )
    merged = host._resolve_routing_params(needs_tools=False, user_query="گزارش")
    assert merged["operation"] == AI_OPERATION_TITLE
    assert merged["user_query"] == "گزارش"
    assert merged["needs_tools"] is False
    host.clear_routing_context()
    fresh = host._resolve_routing_params()
    assert fresh["operation"] == AI_OPERATION_CHAT
    assert fresh["needs_tools"] is False


def test_set_request_model_strips_blank() -> None:
    host = _RouterHost()
    host.set_request_model("  gpt-4o  ")
    assert host._request_model_code == "gpt-4o"
    host.set_request_model("   ")
    assert host._request_model_code is None


def test_routing_needs_tools_respects_flag_and_query() -> None:
    host = _RouterHost()
    assert host._routing_needs_tools(False, "فاکتورهای این ماه", None) is False
    assert host._routing_needs_tools(True, "سلام", None) is False
    assert host._routing_needs_tools(True, "گزارش فروش این ماه را بده", None) is True
