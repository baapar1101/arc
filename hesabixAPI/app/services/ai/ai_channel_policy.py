"""سیاست ابزار per-channel — شروع ماتریس واحد WFA-02 / CHN-02.

کانال‌های جانبی (CRM، تیکت، ورک‌فلو) نباید کاتالوگ کامل چت را ببینند.
اگر کالر لیست ابزار بدهد، حلقه نباید آن را به‌خاطر routing «ساده» دور بریزد.
"""
from __future__ import annotations

from typing import AbstractSet, Any, FrozenSet, Iterable, List, Optional, Tuple

from app.services.ai.ai_write_guard import is_write_function

CHANNEL_CRM_READ_TOOLS: FrozenSet[str] = frozenset(
    {
        "search_leads",
        "get_lead_details",
        "search_deals",
        "get_deal_details",
        "search_activities",
        "get_crm_summary",
        "get_pipeline_report",
        "get_lead_funnel_report",
        "search_persons",
        "get_customer_info",
    }
)

CHANNEL_TICKET_READ_TOOLS: FrozenSet[str] = frozenset(
    {
        "get_business_info",
        "search_invoices",
        "get_invoice_details",
        "get_invoices_count",
        "search_persons",
        "get_customer_info",
        "get_person_balance",
        "get_financial_summary",
        "search_documents",
        "get_document_details",
    }
)

CHANNEL_CRM = "crm"
CHANNEL_TICKET = "ticket"
CHANNEL_TELEGRAM = "telegram"
CHANNEL_WORKFLOW = "workflow"

CHANNEL_ITERATION_CAP = {
    CHANNEL_CRM: 4,
    CHANNEL_TICKET: 4,
}


def allowlist_for_channel(channel: str) -> Optional[FrozenSet[str]]:
    if channel == CHANNEL_CRM:
        return CHANNEL_CRM_READ_TOOLS
    if channel == CHANNEL_TICKET:
        return CHANNEL_TICKET_READ_TOOLS
    return None


def filter_tools_by_allowlist(
    tools: Optional[Iterable[Any]],
    allowlist: AbstractSet[str],
    *,
    allow_writes: bool = False,
    registry=None,
) -> List[Any]:
    """فقط ابزارهای allowlist؛ نوشتنی‌ها مگر allow_writes حذف می‌شوند."""
    if not tools:
        return []
    allowed = {str(n) for n in allowlist}
    out: List[Any] = []
    for item in tools:
        if not isinstance(item, dict):
            continue
        name = (item.get("function") or {}).get("name")
        if not name or str(name) not in allowed:
            continue
        if not allow_writes and is_write_function(str(name), registry):
            continue
        out.append(item)
    return out


def resolve_round_tool_offer(
    *,
    provided_tools: Optional[List[Any]],
    provider_allows_tools: bool,
    routing_needs_tools: bool,
) -> Tuple[str, Optional[List[Any]]]:
    """تصمیم کاتالوگ یک نوبت.

    برمی‌گرداند: ``load`` (کاتالوگ intent)، ``keep`` (لیست کالر)، ``none``.
    """
    if not provider_allows_tools:
        return "none", None
    if provided_tools is not None:
        return "keep", list(provided_tools)
    if routing_needs_tools:
        return "load", None
    return "none", None


def apply_iteration_cap(adaptive: int, cap: Optional[int]) -> int:
    n = max(1, int(adaptive))
    if cap is None:
        return n
    return max(1, min(n, int(cap)))
