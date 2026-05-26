"""
کنترل عملیات نوشتنی AI — نیاز به تأیید صریح کاربر.
"""
from __future__ import annotations

from typing import Any, Dict, Set

# توابعی که دادهٔ کسب‌وکار را تغییر می‌دهند و قبل از اجرا نیاز به تأیید دارند.
WRITE_FUNCTIONS: Set[str] = {
    "create_invoice",
    "create_person",
    "update_person",
    "create_receipt_payment",
}

WRITE_FUNCTION_LABELS_FA: Dict[str, str] = {
    "create_invoice": "ثبت فاکتور",
    "create_person": "ایجاد شخص",
    "update_person": "ویرایش شخص",
    "create_receipt_payment": "ثبت دریافت/پرداخت",
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
