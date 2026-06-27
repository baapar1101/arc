"""Helper utilities for support ticket notifications."""

from __future__ import annotations


def support_ticket_deep_link(ticket_id: int) -> str:
    return f"/user/profile/support/tickets/{ticket_id}"


def support_operator_deep_link(ticket_id: int) -> str:
    return f"/user/profile/operator?ticket={ticket_id}"


def support_notification_context(base: dict, ticket_id: int) -> dict:
    ctx = dict(base)
    ctx["deep_link"] = support_ticket_deep_link(ticket_id)
    ctx["action_url"] = support_ticket_deep_link(ticket_id)
    return ctx


def support_operator_notification_context(base: dict, ticket_id: int) -> dict:
    ctx = dict(base)
    ctx["deep_link"] = support_operator_deep_link(ticket_id)
    ctx["action_url"] = support_operator_deep_link(ticket_id)
    return ctx
