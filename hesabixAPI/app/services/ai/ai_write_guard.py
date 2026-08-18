"""
کنترل عملیات نوشتنی AI — نیاز به تأیید صریح کاربر.

دو روش تشخیص (اولویت با registry):
  1. registry-based: AIFunction.requires_approval = True
  2. static fallback: WRITE_FUNCTIONS (برای backward compat)
"""
from __future__ import annotations

import json
import uuid
from typing import Any, Callable, Dict, Iterable, List, Optional, Set, Tuple

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
    آیا function نیاز به تأیید دارد.

    اگر registry داده شود منبع حقیقت همان است؛ نام ناشناخته fail-closed
    است (write فرض می‌شود) تا مسیر MCP/ورک‌فلو ابزار جدید را بی‌تأیید اجرا نکند.
    بدون registry به WRITE_FUNCTIONS برمی‌گردد.
    """
    if registry is not None:
        fn = registry.get_function(name)
        if fn is not None:
            return bool(getattr(fn, "requires_approval", False))
        return True
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
        return False
    return name not in WRITE_FUNCTIONS


def is_agent_internal_function(name: str, registry=None) -> bool:
    """state داخلی agent — تغییر دادهٔ کسب‌وکار نیست."""
    if registry is not None:
        fn = registry.get_function(name)
        if fn is not None:
            return bool(getattr(fn, "is_agent_internal", False))
    return False


def _canonical_json(value: Any) -> str:
    return json.dumps(value or {}, ensure_ascii=False, sort_keys=True, separators=(",", ":"), default=str)


def write_function_label(function_name: str) -> str:
    return TOOL_LABELS_FA.get(function_name) or WRITE_FUNCTION_LABELS_FA.get(
        function_name, function_name
    )


def argument_diff(approved: Dict[str, Any], requested: Dict[str, Any]) -> Dict[str, Any]:
    """کلیدهایی که بین کارت تأیید و درخواست جدید فرق دارند."""
    keys = set(approved or ()) | set(requested or ())
    changed: Dict[str, Any] = {}
    for key in keys:
        left = (approved or {}).get(key)
        right = (requested or {}).get(key)
        if _canonical_json(left) != _canonical_json(right):
            changed[key] = {"approved": left, "requested": right}
    return changed


def resolve_approved_write(
    function_name: str,
    arguments: Dict[str, Any],
    approved_write_calls: Iterable[Dict[str, Any]] | None,
) -> Tuple[bool, Dict[str, Any], Optional[Dict[str, Any]]]:
    """تأیید روی approval_id / کارت واحد؛ آرگومان ذخیره‌شده اجرا می‌شود (SEC-01).

    خروجی: (ok, args_to_execute, mismatch_meta)
    """
    same_fn = [
        dict(item)
        for item in (approved_write_calls or [])
        if isinstance(item, dict) and item.get("function") == function_name
    ]
    requested = arguments or {}
    for approved in same_fn:
        stored = approved.get("arguments") if isinstance(approved.get("arguments"), dict) else {}
        if _canonical_json(stored) == _canonical_json(requested):
            return True, dict(stored), None
    if len(same_fn) == 1:
        stored = (
            same_fn[0].get("arguments")
            if isinstance(same_fn[0].get("arguments"), dict)
            else {}
        )
        aid = same_fn[0].get("approval_id")
        if aid or stored:
            diff = argument_diff(stored, requested)
            return True, dict(stored), ({"approval_id": aid, "arg_diff": diff} if diff else None)
    return False, dict(requested), None


def write_call_is_approved(
    function_name: str,
    arguments: Dict[str, Any],
    approved_write_calls: Iterable[Dict[str, Any]] | None,
) -> bool:
    ok, _, _ = resolve_approved_write(function_name, arguments, approved_write_calls)
    return ok


def is_approval_required_result(result: Any) -> bool:
    return isinstance(result, dict) and result.get("error") == "APPROVAL_REQUIRED"


def is_write_guard_stop_result(result: Any) -> bool:
    """نتیجه‌ای که باید حلقه agent برای تأیید کاربر متوقف شود.

    APPROVAL_MISMATCH ابزار را رد می‌کند ولی نباید دوباره کارت تأیید نشان دهد؛
    مدل باید نتیجه را ببیند و با آرگومان تأییدشده دوباره تلاش کند.
    """
    return is_approval_required_result(result)


def build_approval_pause_content(
    function_calls: List[Dict[str, Any]],
    lookup_result: Callable[[Dict[str, Any]], Any],
) -> str:
    """متن کوتاه برای نمایش به کاربر هنگام توقف agent برای تأیید."""
    labels: List[str] = []
    for call in function_calls:
        result = lookup_result(call)
        if is_approval_required_result(result):
            label = result.get("label") or result.get("function") or call.get("name") or "عملیات"
            labels.append(str(label))
    if not labels:
        return (
            "برای ادامه، لطفاً عملیات پیشنهادی را در کارت زیر بررسی کرده و تأیید یا رد کنید."
        )
    if len(labels) == 1:
        return (
            f"عملیات «{labels[0]}» آماده اجراست. "
            "جزئیات را بررسی کنید و در صورت موافقت، تأیید کنید."
        )
    joined = "، ".join(f"«{l}»" for l in labels[:4])
    suffix = f" و {len(labels) - 4} مورد دیگر" if len(labels) > 4 else ""
    return (
        f"{len(labels)} عملیات ({joined}{suffix}) نیاز به تأیید شما دارند. "
        "لطفاً موارد را بررسی کرده و تأیید کنید."
    )


def build_approval_required_result(function_name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
    label = write_function_label(function_name)
    return {
        "error": "APPROVAL_REQUIRED",
        "status": "pending_approval",
        "approval_id": uuid.uuid4().hex[:16],
        "function": function_name,
        "label": label,
        "arguments": arguments,
        "message": (
            f"عملیات «{label}» نیاز به تأیید صریح کاربر دارد. "
            "خلاصهٔ درخواست را برای کاربر توضیح دهید و از او بخواهید تأیید کند."
        ),
    }


def is_approval_block_result(result: Any) -> bool:
    """نتیجه‌ای که agent باید برای آن منتظر تأیید/هماهنگی کاربر بماند."""
    return isinstance(result, dict) and result.get("error") in (
        "APPROVAL_REQUIRED",
        "APPROVAL_MISMATCH",
    )


def extract_pending_approval_ops(function_results: Any) -> List[Dict[str, Any]]:
    """کارت‌های APPROVAL_REQUIRED از function_results (کانال چت/تلگرام)."""
    ops: List[Dict[str, Any]] = []
    if isinstance(function_results, dict):
        values = function_results.values()
    elif isinstance(function_results, list):
        values = function_results
    else:
        return ops
    for value in values:
        payload = approval_payload_from_result_entry(value)
        if payload:
            ops.append(payload)
    return dedupe_pending_approval_ops(ops)


def dedupe_pending_approval_ops(ops: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """حذف تکرار ناشی از ذخیرهٔ همزمان tool_call_id و نام ابزار."""
    seen: set[str] = set()
    out: List[Dict[str, Any]] = []
    for op in ops:
        if not isinstance(op, dict):
            continue
        aid = op.get("approval_id")
        if isinstance(aid, str) and aid.strip():
            key = f"id:{aid.strip()}"
        else:
            fn = str(op.get("function") or "")
            key = f"fn:{fn}:{_canonical_json(op.get('arguments'))}"
        if key in seen:
            continue
        seen.add(key)
        out.append(op)
    return out


def approval_payload_from_result_entry(entry: Any) -> Optional[Dict[str, Any]]:
    raw = entry
    if isinstance(raw, dict) and isinstance(raw.get("result"), dict):
        nested = raw["result"]
        if nested.get("error") == "APPROVAL_REQUIRED":
            raw = nested
    if not isinstance(raw, dict) or raw.get("error") != "APPROVAL_REQUIRED":
        return None
    function_name = raw.get("function") or raw.get("name")
    arguments = raw.get("arguments")
    if not isinstance(function_name, str) or not isinstance(arguments, dict):
        return None
    payload: Dict[str, Any] = {"function": function_name, "arguments": arguments}
    aid = raw.get("approval_id")
    if isinstance(aid, str) and aid.strip():
        payload["approval_id"] = aid.strip()
    label = raw.get("label")
    if isinstance(label, str) and label.strip():
        payload["label"] = label.strip()
    return payload


def resolve_tool_result(function_results: Dict[str, Any], call: Dict[str, Any]) -> Any:
    """یافتن نتیجه tool (سازگار با ai_service._lookup_tool_result)."""
    tc_id = call.get("id")
    if tc_id and tc_id in function_results:
        val = function_results[tc_id]
        if isinstance(val, dict) and "result" in val:
            return val["result"]
        return val
    name = call.get("name")
    if name and name in function_results:
        val = function_results[name]
        if isinstance(val, dict) and "result" in val and "name" in val:
            return val.get("result")
        return val
    return {}


def round_needs_approval_pause(function_results: Dict[str, Any]) -> bool:
    """آیا این round باید agent loop را متوقف کند تا کاربر تأیید کند؟"""
    seen: set[str] = set()
    for key, val in function_results.items():
        if str(key).startswith("_"):
            continue
        if isinstance(val, dict) and "result" in val and "name" in val:
            dedupe = str(key)
            if dedupe in seen:
                continue
            seen.add(dedupe)
            if is_approval_block_result(val.get("result")):
                return True
        elif is_approval_block_result(val):
            dedupe = str(key)
            if dedupe in seen:
                continue
            seen.add(dedupe)
            return True
    return False


def collect_approval_block_results(
    function_results: Dict[str, Any],
    function_calls: Optional[List[Dict[str, Any]]] = None,
) -> List[Dict[str, Any]]:
    """استخراج نتایج APPROVAL_* از یک round (بدون تکرار)."""
    out: List[Dict[str, Any]] = []
    seen_keys: set[str] = set()
    calls = function_calls or []
    if calls:
        for call in calls:
            result = resolve_tool_result(function_results, call)
            if not is_approval_block_result(result):
                continue
            fn = call.get("name") or result.get("function")
            key = f"{fn}:{_canonical_json(result.get('arguments'))}"
            if key in seen_keys:
                continue
            seen_keys.add(key)
            out.append(result if isinstance(result, dict) else {})
        return out
    for val in function_results.values():
        result = val.get("result") if isinstance(val, dict) and "result" in val else val
        if not is_approval_block_result(result):
            continue
        fn = result.get("function") if isinstance(result, dict) else None
        key = f"{fn}:{_canonical_json(result.get('arguments') if isinstance(result, dict) else {})}"
        if key in seen_keys:
            continue
        seen_keys.add(key)
        out.append(result if isinstance(result, dict) else {})
    return out


def build_approval_pause_message(
    function_results: Dict[str, Any],
    function_calls: Optional[List[Dict[str, Any]]] = None,
) -> str:
    """پیام کوتاه برای نمایش در چت هنگام توقف برای تأیید."""
    blocks = collect_approval_block_results(function_results, function_calls)
    if not blocks:
        return (
            "برای ادامه، عملیات پیشنهادی نیاز به تأیید شما دارد. "
            "لطفاً در کارت بالای صفحه تأیید یا لغو کنید."
        )
    lines: List[str] = [
        "برای اجرای عملیات زیر به تأیید شما نیاز دارم:",
        "",
    ]
    for entry in blocks:
        label = entry.get("label") or entry.get("function") or "عملیات"
        hint = entry.get("message")
        if hint:
            lines.append(f"- **{label}**: {hint}")
        else:
            lines.append(f"- **{label}**")
    lines.extend(
        [
            "",
            "پس از بررسی، با دکمه **تأیید و اجرا** موافقت کنید یا **لغو** را بزنید.",
        ]
    )
    return "\n".join(lines)


def build_read_only_mode_result(function_name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
    label = write_function_label(function_name)
    return {
        "error": "READ_ONLY_MODE",
        "status": "blocked",
        "function": function_name,
        "label": label,
        "arguments": arguments,
        "message": (
            f"عملیات «{label}» در حالت تحلیلگر مجاز نیست. "
            "فقط خواندن و تحلیل داده‌ها امکان‌پذیر است. "
            "اگر کاربر می‌خواهد تغییر ثبت شود، از او بخواهید حالت اجرا را به "
            "«با تأیید من» یا «خودکار» تغییر دهد."
        ),
    }


def is_read_only_mode_result(result: Any) -> bool:
    return isinstance(result, dict) and result.get("error") == "READ_ONLY_MODE"


def build_approval_mismatch_result(
    function_name: str,
    arguments: Dict[str, Any],
    *,
    arg_diff: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    label = write_function_label(function_name)
    payload: Dict[str, Any] = {
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
    if arg_diff:
        payload["arg_diff"] = arg_diff
    return payload
