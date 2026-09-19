"""Helper utilities for support ticket notifications."""

from __future__ import annotations

from typing import Any, Dict, Optional


OPERATOR_INBOX_PATH = "/user/profile/operator"
USER_SUPPORT_INBOX_PATH = "/user/profile/support"

OPERATOR_TICKET_EVENTS = frozenset({
    "support.ticket_created",
    "support.user_reply",
    "support.ticket_assigned",
    "support.tickets_bulk_assigned",
})

USER_TICKET_EVENTS = frozenset({
    "support.operator_reply",
    "support.ticket_status_changed",
    "support.tickets_bulk_status_changed",
})


def support_ticket_deep_link(ticket_id: int) -> str:
    return f"/user/profile/support/tickets/{ticket_id}"


def support_operator_deep_link(ticket_id: int) -> str:
    return f"/user/profile/operator?ticket={ticket_id}"


def support_notification_context(base: dict, ticket_id: int) -> dict:
    ctx = dict(base)
    ctx["ticket_id"] = ticket_id
    ctx["deep_link"] = support_ticket_deep_link(ticket_id)
    ctx["action_url"] = support_ticket_deep_link(ticket_id)
    return ctx


def support_operator_notification_context(base: dict, ticket_id: int) -> dict:
    ctx = dict(base)
    ctx["ticket_id"] = ticket_id
    ctx["deep_link"] = support_operator_deep_link(ticket_id)
    ctx["action_url"] = support_operator_deep_link(ticket_id)
    return ctx


def _parse_ticket_id(value: Any) -> Optional[int]:
    if value is None:
        return None
    try:
        parsed = int(value)
        return parsed if parsed > 0 else None
    except (TypeError, ValueError):
        return None


def resolve_announcement_navigation(event_key: str, context: Dict[str, Any]) -> Dict[str, Optional[Any]]:
    """Resolve deep_link and ticket_id for in-app announcement persistence."""
    ticket_id = _parse_ticket_id(context.get("ticket_id"))
    deep_link = context.get("deep_link") or context.get("action_url")
    if deep_link:
        return {"deep_link": str(deep_link), "ticket_id": ticket_id, "event_key": event_key or None}

    key = (event_key or "").strip()

    if ticket_id:
        if key in OPERATOR_TICKET_EVENTS or key == "support.ticket_assigned":
            return {
                "deep_link": support_operator_deep_link(ticket_id),
                "ticket_id": ticket_id,
                "event_key": key or None,
            }
        if key in USER_TICKET_EVENTS or key == "support.operator_reply":
            return {
                "deep_link": support_ticket_deep_link(ticket_id),
                "ticket_id": ticket_id,
                "event_key": key or None,
            }
        if key.startswith("support."):
            if "operator" in key or key.endswith("_assigned") or key.endswith("_created"):
                return {
                    "deep_link": support_operator_deep_link(ticket_id),
                    "ticket_id": ticket_id,
                    "event_key": key,
                }
            return {
                "deep_link": support_ticket_deep_link(ticket_id),
                "ticket_id": ticket_id,
                "event_key": key,
            }

    if key == "support.tickets_bulk_assigned":
        return {"deep_link": OPERATOR_INBOX_PATH, "ticket_id": None, "event_key": key}
    if key == "support.tickets_bulk_status_changed":
        return {"deep_link": USER_SUPPORT_INBOX_PATH, "ticket_id": None, "event_key": key}
    if key.startswith("support."):
        if key in OPERATOR_TICKET_EVENTS:
            return {"deep_link": OPERATOR_INBOX_PATH, "ticket_id": None, "event_key": key}
        if key in USER_TICKET_EVENTS:
            return {"deep_link": USER_SUPPORT_INBOX_PATH, "ticket_id": None, "event_key": key}

    return {"deep_link": None, "ticket_id": ticket_id, "event_key": key or None}
