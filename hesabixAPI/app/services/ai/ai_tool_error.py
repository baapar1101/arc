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
    hint_fa = (
        "آرگومان را مطابق schema همین ابزار اصلاح کن؛ همان JSON قبلی را تکرار نکن. "
        "شناسه‌ها را از ابزارهای search/list بگیر."
    )
    message_fa = "اجرای ابزار با خطا مواجه شد."
    retryable = True

    unexpected = _UNEXPECTED_KW.search(raw)
    if unexpected:
        code = "INVALID_ARGUMENTS"
        bad = unexpected.group(1)
        if bad in {"db", "user_id", "business_id"}:
            message_fa = "آرگومان داخلی سیستم به‌اشتباه به ابزار رسید."
            hint_fa = (
                "db/user_id/business_id را نفرست؛ جلسه آن‌ها را تزریق می‌کند. "
                "فقط فیلدهای schema همین ابزار را بفرست."
            )
        else:
            message_fa = f"پارامتر «{bad}» برای این ابزار معتبر نیست."
            hint_fa = (
                f"آرگومان «{bad}» را حذف کن و فقط فیلدهای schema همین ابزار را بفرست."
            )
    elif _NOT_FOUND.search(raw) or "not found in registry" in raw.lower():
        return unknown_tool_result(function_name)
    elif _is_api_error(exc):
        code = str(getattr(exc, "code", None) or getattr(exc, "error_code", None) or "TOOL_ERROR")
        api_message = str(getattr(exc, "message", None) or raw)
        message_fa = api_message if _looks_persian(api_message) else (
            api_message if api_message else "اجرای ابزار با خطا مواجه شد."
        )
        hint_fa = _hint_for_business_code(code, function_name, api_message)
    elif isinstance(exc, PermissionError):
        code = "PERMISSION_DENIED"
        message_fa = "اجازهٔ اجرای این ابزار را ندارید."
        hint_fa = "این عملیات را پیشنهاد نده یا از کاربر بخواه دسترسی را بررسی کند."
        retryable = False
    elif isinstance(exc, ValueError) or _MISSING_ARG.search(raw):
        code = "INVALID_ARGUMENTS"
        message_fa = raw if _looks_persian(raw) else "پارامترهای ابزار ناقص یا نامعتبر است."
        hint_fa = raw if _looks_persian(raw) else hint_fa
        if "فیلتر" in raw and "مجاز نیست" in raw:
            hint_fa = (
                f"{raw} نام ستون را حدس نزن؛ list_queryable_fields را صدا بزن "
                "یا از پارامتر search برای نام/کد استفاده کن."
            )

    expected = _schema_property_names(schema)
    required = _schema_required_names(schema)
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
    if required:
        payload["required_args"] = required
    if raw and raw != message_fa:
        payload["detail"] = raw[:400]
    return payload


_BUSINESS_HINTS: Dict[str, str] = {
    "PERSON_REQUIRED": (
        "person_id عددی مشتری را از search_persons بردار و در ریشهٔ آرگومان بفرست. "
        "نام شخص به‌جای شناسه قبول نیست."
    ),
    "CURRENCY_REQUIRED": (
        "currency_id را با list_currencies بگیر یا خالی بگذار تا ارز پیش‌فرض کسب‌وکار استفاده شود."
    ),
    "LINES_REQUIRED": "حداقل یک سطر در lines با product_id، quantity و در فاکتور unit_price بفرست.",
    "INVALID_LINE": "هر سطر باید product_id و quantity مثبت داشته باشد.",
    "INVALID_INVOICE_TYPE": (
        "invoice_type را یکی از invoice_sales / invoice_purchase / "
        "invoice_sales_return / invoice_purchase_return بگذار."
    ),
    "PERSON_NOT_FOUND_OR_WRONG_BUSINESS": (
        "person_id متعلق به این کسب‌وکار نیست. دوباره search_persons را در همین کسب‌وکار صدا بزن."
    ),
    "PERSON_LINES_REQUIRED": "person_id عددی را از search_persons بگیر و همراه amount بفرست.",
    "ACCOUNT_LINES_REQUIRED": (
        "account_type=bank|cash_register|petty_cash و account_id را از "
        "list_bank_accounts / list_cash_registers / list_petty_cash بگیر — نه از list_accounts."
    ),
    "ACCOUNT_NOT_FOUND": (
        "account_id کدینگ نیست. برای دریافت/پرداخت از list_bank_accounts یا list_cash_registers استفاده کن."
    ),
    "UNBALANCED_AMOUNTS": "مبلغ شخص و مبلغ حساب باید برابر باشد.",
    "INVALID_CHECK_TYPE": "type چک فقط received یا transferred است.",
    "CHECK_NUMBER_REQUIRED": "check_number را بفرست.",
    "INVALID_AMOUNT": "amount باید عدد بزرگتر از صفر باشد.",
    "INVALID_SOURCE": "from_account_type باید bank یا cash_register یا petty_cash باشد.",
    "INVALID_DESTINATION": "to_account_type باید bank یا cash_register یا petty_cash باشد.",
    "INVALID_DOC_TYPE": "doc_type حواله: receipt (ورود)، issue (خروج)، transfer، adjustment.",
    "WAREHOUSE_REQUIRED": "شناسه انبار را از list_warehouses بگیر.",
    "WAREHOUSES_REQUIRED": "برای انتقال، warehouse_id_from و warehouse_id_to هر دو لازم است.",
    "PRODUCT_REQUIRED": "product_id را از search_products بگیر.",
    "DATE_REQUIRED": "document_date را YYYY-MM-DD یا شمسی بفرست؛ یا خالی بگذار تا امروز استفاده شود.",
}


def _hint_for_business_code(code: str, function_name: str, api_message: str) -> str:
    mapped = _BUSINESS_HINTS.get(code)
    if mapped:
        return mapped
    if _looks_persian(api_message):
        return api_message
    if function_name == "create_invoice":
        return (
            "آرگومان create_invoice را با person_id، invoice_type=invoice_sales یا invoice_purchase، "
            "و lines[].product_id/quantity/unit_price کامل کن."
        )
    if function_name == "create_receipt_payment":
        return (
            "type=receipt|payment، person_id از search_persons، "
            "account_type و account_id از لیست بانک/صندوق — نه کدینگ."
        )
    if function_name == "create_check":
        return "type=received|transferred، check_number، amount، تاریخ صدور/سررسید، و برای دریافتی person_id."
    if function_name == "create_warehouse_document":
        return (
            "doc_type=receipt|issue|transfer، انبار از list_warehouses، "
            "و lines با product_id و quantity."
        )
    if function_name in {"create_workflow", "update_workflow", "validate_workflow_draft"}:
        return (
            "workflow_data باید {nodes, connections} باشد. "
            "get_workflow_design_rules و validate_workflow_draft را اول صدا بزن."
        )
    return "آرگومان را مطابق قرارداد ابزار اصلاح کن و دوباره تلاش کن."


def _schema_property_names(schema: Optional[Dict[str, Any]]) -> list[str]:
    if not isinstance(schema, dict):
        return []
    props = schema.get("properties")
    if not isinstance(props, dict):
        return []
    names = [str(k) for k in props.keys()]
    for nest_key in ("lines", "person_lines", "account_lines", "item_lines"):
        nested_node = props.get(nest_key)
        if not isinstance(nested_node, dict):
            continue
        items = nested_node.get("items")
        nested = (items or {}).get("properties") if isinstance(items, dict) else None
        if isinstance(nested, dict):
            names.extend(f"{nest_key}[].{k}" for k in nested.keys())
    wd = props.get("workflow_data")
    if isinstance(wd, dict):
        names.extend(["workflow_data.nodes", "workflow_data.connections"])
    return names[:36]


def _schema_required_names(schema: Optional[Dict[str, Any]]) -> list[str]:
    if not isinstance(schema, dict):
        return []
    req = schema.get("required")
    if not isinstance(req, list):
        return []
    return [str(x) for x in req if x][:24]


def _is_api_error(exc: BaseException) -> bool:
    return type(exc).__name__ == "ApiError" or (
        hasattr(exc, "error_code") and hasattr(exc, "message")
    )


def _looks_persian(text: str) -> bool:
    return any("\u0600" <= ch <= "\u06FF" for ch in text or "")
