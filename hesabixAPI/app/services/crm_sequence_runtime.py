"""قواعد خالص آهنگ فروش: متن پیامک، سقف روزانه و قالب گردش‌کار تخفیف."""
from __future__ import annotations

import re
from typing import Any

_TOKEN = re.compile(r"\{\{\s*([a-zA-Z0-9_]+)\s*\}\}")
DISCOUNT_APPROVAL_WORKFLOW_NAME = "تأیید تخفیف فاکتور فروش"


def render_sequence_sms(template: str | None, values: dict[str, Any] | None) -> str:
    text = template or ""
    data = values or {}

    def replace(match: re.Match) -> str:
        key = match.group(1)
        if key not in data or data[key] is None:
            return ""
        return str(data[key])

    return _TOKEN.sub(replace, text).strip()


def sms_send_allowed(sent_today: int, daily_cap: int | None) -> bool:
    if daily_cap is None or daily_cap <= 0:
        return True
    return sent_today < daily_cap


def discount_approval_workflow_data(business_id: int, threshold: float = 0) -> dict[str, Any]:
    """پیش‌نویس گردش‌کار روی موتور موجود. تا فعال‌سازی در ویرایشگر اجرا نمی‌شود."""
    return {
        "nodes": [
            {
                "id": "invoice_trigger",
                "type": "trigger",
                "label": "ایجاد فاکتور فروش",
                "config": {"trigger_type": "invoice.sales.created"},
            },
            {
                "id": "discount_check",
                "type": "condition",
                "label": "تخفیف از سقف بیشتر است",
                "config": {
                    "condition_type": "simple",
                    "left_value": "$invoice_trigger.discount_amount",
                    "operator": ">",
                    "right_value": threshold,
                },
            },
            {
                "id": "ask_approval",
                "type": "action",
                "label": "درخواست تأیید تخفیف",
                "config": {
                    "action_type": "create_notification",
                    "event_key": "crm.follow_up_due",
                    "title": "تأیید تخفیف فاکتور",
                    "message": "فاکتور $invoice_trigger.invoice_code تخفیف $invoice_trigger.discount_amount دارد و باید پیش از ادامه تأیید شود.",
                    "channels": ["inapp"],
                    "deep_link": f"/business/{int(business_id)}/invoice/$invoice_trigger.invoice_id/edit",
                },
            },
        ],
        "connections": [
            {"source": "invoice_trigger", "target": "discount_check"},
            {"source": "discount_check", "target": "ask_approval", "sourceHandle": "true"},
        ],
    }


def crm_notification_path(
    business_id: int,
    entity_type: str,
    entity_id: int,
    *,
    deal_id: int | None = None,
    lead_id: int | None = None,
) -> str:
    if entity_type == "lead":
        return f"/business/{business_id}/crm/leads/{entity_id}"
    if entity_type == "deal":
        return f"/business/{business_id}/crm/deals/{entity_id}"
    if deal_id:
        return f"/business/{business_id}/crm/deals/{deal_id}"
    if lead_id:
        return f"/business/{business_id}/crm/leads/{lead_id}"
    return f"/business/{business_id}/crm/tasks"
