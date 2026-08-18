"""نرمال‌سازی خطای ابزار برای مدل — قابل بازیابی، فارسی، بدون stack خام."""
from __future__ import annotations

import re
from typing import Any, Dict, Optional

_UNEXPECTED_KW = re.compile(
    r"got an unexpected keyword argument ['\"]([^'\"]+)['\"]",
    re.IGNORECASE,
)
_MISSING_ARG = re.compile(
    r"missing \d+ required positional argument",
    re.IGNORECASE,
)
_NOT_FOUND = re.compile(
    r"Function ['\"]([^'\"]+)['\"] not found",
    re.IGNORECASE,
)


def unknown_tool_result(function_name: str) -> Dict[str, Any]:
    name = (function_name or "unknown").strip() or "unknown"
    return {
        "ok": False,
        "error": "UNKNOWN_TOOL",
        "tool": name,
        "message": f"ابزار «{name}» در کاتالوگ این نوبت وجود ندارد.",
        "message_fa": f"ابزار «{name}» وجود ندارد.",
        "hint_fa": (
            "فقط از نام ابزارهایی استفاده کن که در همین نوبت به تو داده شده‌اند. "
            "نام را حدس نزن و برای ابزار ناموجود تأیید نوشتن نخواه."
        ),
        "retryable": True,
    }


def normalize_tool_error(
    function_name: str,
    exc: BaseException,
    *,
    schema: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    raw = str(exc).strip() or type(exc).__name__
    code = "TOOL_ERROR"
    hint_fa = "آرگومان را بدون تکرار عینی قبلی اصلاح کن و دوباره تلاش کن."
    message_fa = "اجرای ابزار با خطا مواجه شد."
    retryable = True

    unexpected = _UNEXPECTED_KW.search(raw)
    if unexpected:
        code = "INVALID_ARGUMENTS"
        bad = unexpected.group(1)
        message_fa = f"پارامتر «{bad}» برای این ابزار معتبر نیست."
        hint_fa = (
            f"آرگومان «{bad}» را حذف کن و فقط فیلدهای schema همین ابزار را بفرست."
        )
    elif _NOT_FOUND.search(raw) or "not found in registry" in raw.lower():
        return unknown_tool_result(function_name)
    elif isinstance(exc, PermissionError):
        code = "PERMISSION_DENIED"
        message_fa = "اجازهٔ اجرای این ابزار را ندارید."
        hint_fa = "این عملیات را پیشنهاد نده یا از کاربر بخواه دسترسی را بررسی کند."
        retryable = False
    elif isinstance(exc, ValueError) or _MISSING_ARG.search(raw):
        code = "INVALID_ARGUMENTS"
        message_fa = raw if _looks_persian(raw) else "پارامترهای ابزار ناقص یا نامعتبر است."
        hint_fa = raw if _looks_persian(raw) else hint_fa

    expected = _schema_property_names(schema)
    payload: Dict[str, Any] = {
        "ok": False,
        "error": code,
        "tool": function_name,
        "message": message_fa,
        "message_fa": message_fa,
        "hint_fa": hint_fa,
        "retryable": retryable,
    }
    if expected:
        payload["expected_args"] = expected
    if raw and raw != message_fa:
        payload["detail"] = raw[:400]
    return payload


def _schema_property_names(schema: Optional[Dict[str, Any]]) -> list[str]:
    if not isinstance(schema, dict):
        return []
    props = schema.get("properties")
    if not isinstance(props, dict):
        return []
    return [str(k) for k in props.keys()][:24]


def _looks_persian(text: str) -> bool:
    return any("\u0600" <= ch <= "\u06FF" for ch in text or "")
