"""
کنترل عملیات نوشتنی AI — نیاز به تأیید صریح کاربر.

دو روش تشخیص (اولویت با registry):
  1. registry-based: AIFunction.requires_approval = True
  2. static fallback: WRITE_FUNCTIONS (برای backward compat)
"""
from __future__ import annotations

import json
from typing import Any, Dict, Iterable, Optional, Set

from app.services.ai.ai_tool_keys import TOOL_LABELS_FA

# Fallback static list — تا زمانی که registry آماده نشده
WRITE_FUNCTIONS: Set[str] = {
    "create_invoice",
    "create_person",
    "update_person",
    "create_receipt_payment",
    "delete_person",
    "create_product",
    "update_product",
    "create_check",
    "create_transfer",
    "create_expense_income",
    "update_invoice",
    "delete_invoice",
    "create_lead",
    "execute_workflow",
    "create_workflow",
    "update_workflow",
    "delete_workflow",
    "export_business_data",
    "set_default_report_template",
    "publish_report_template",
    "adjust_customer_club_points",
    "recalculate_customer_club_rfm",
    "update_customer_club_settings",
    "update_user_memory",
}

WRITE_FUNCTION_LABELS_FA: Dict[str, str] = {
    name: TOOL_LABELS_FA[name]
    for name in WRITE_FUNCTIONS
    if name in TOOL_LABELS_FA
}


def is_write_function(name: str, registry=None) -> bool:
    """
    بررسی اینکه آیا function نیاز به تأیید دارد.
    اگر registry داده شود از AIFunction.requires_approval استفاده می‌کند؛
    در غیر این صورت به WRITE_FUNCTIONS static برمی‌گردد.
    """
    if registry is not None:
        fn = registry.get_function(name)
        if fn is not None:
            return bool(getattr(fn, "requires_approval", False))
    return name in WRITE_FUNCTIONS


def get_risk_level(name: str, registry=None) -> str:
    """سطح ریسک function: safe / medium / high."""
    if registry is not None:
        fn = registry.get_function(name)
        if fn is not None:
            return getattr(fn, "risk_level", "safe")
    if name in WRITE_FUNCTIONS:
        return "medium"
    return "safe"


def is_readonly_function(name: str, registry=None) -> bool:
    """آیا function فقط خواندنی است (قابل کش)؟"""
    if registry is not None:
        fn = registry.get_function(name)
        if fn is not None:
            return bool(getattr(fn, "is_readonly", True))
    return name not in WRITE_FUNCTIONS


def _canonical_json(value: Any) -> str:
    return json.dumps(value or {}, ensure_ascii=False, sort_keys=True, separators=(",", ":"), default=str)


def write_call_is_approved(
    function_name: str,
    arguments: Dict[str, Any],
    approved_write_calls: Iterable[Dict[str, Any]] | None,
) -> bool:
    target_args = _canonical_json(arguments)
    for approved in approved_write_calls or []:
        if approved.get("function") != function_name:
            continue
        if _canonical_json(approved.get("arguments")) == target_args:
            return True
    return False


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


def build_approval_mismatch_result(function_name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
    label = WRITE_FUNCTION_LABELS_FA.get(function_name, function_name)
    return {
        "error": "APPROVAL_MISMATCH",
        "status": "rejected",
        "function": function_name,
        "label": label,
        "arguments": arguments,
        "message": (
            f"عملیات «{label}» با درخواست تأییدشده قبلی تطابق ندارد. "
            "برای امنیت، لطفاً خلاصه عملیات جدید را دوباره به کاربر نشان دهید و تأیید بگیرید."
        ),
    }
