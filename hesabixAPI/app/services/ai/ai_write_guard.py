"""
کنترل عملیات نوشتنی AI — نیاز به تأیید صریح کاربر.
"""
from __future__ import annotations

from typing import Any, Dict, Set

from app.services.ai.ai_tool_keys import TOOL_LABELS_FA

# توابعی که دادهٔ کسب‌وکار را تغییر می‌دهند و قبل از اجرا نیاز به تأیید دارند.
WRITE_FUNCTIONS: Set[str] = {
    "create_invoice",
    "create_person",
    "update_person",
    "create_receipt_payment",
}

WRITE_FUNCTION_LABELS_FA: Dict[str, str] = {
    name: TOOL_LABELS_FA[name]
    for name in WRITE_FUNCTIONS
    if name in TOOL_LABELS_FA
}


def is_write_function(name: str) -> bool:
    return name in WRITE_FUNCTIONS


def build_approval_required_result(function_name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
    label = WRITE_FUNCTION_LABELS_FA.get(function_name, function_name)
    return {
        "error": "APPROVAL_REQUIRED",
        "status": "pending_approval",
        "function": function_name,
        "label": label,
        "arguments": arguments,
        "message": (
            f"عملیات «{label}» نیاز به تأیید صریح کاربر دارد. "
            "خلاصهٔ درخواست را برای کاربر توضیح دهید و از او بخواهید تأیید کند."
        ),
    }
