from __future__ import annotations

from typing import Any, Dict, List

from adapters.db.models.tax_setting import TaxSetting


def build_tax_invoice_payload(document: Dict[str, Any], tax_setting: TaxSetting) -> Dict[str, Any]:
    """
    ساختاردهی داده‌های فاکتور بر اساس فرمت مورد انتظار سرویس مودیان.
    این تابع از اطلاعات snapshot شده در خطوط فاکتور استفاده می‌کند تا
    کمترین وابستگی را به کوئری‌های اضافی داشته باشد.
    """
    extra = document.get("extra_info") or {}
    totals = extra.get("totals") or {}
    person_snapshot = (
        extra.get("person_snapshot")
        or extra.get("person_info")
        or {}
    )

    header = {
        "tax_memory_id": tax_setting.tax_memory_id,
        "economic_code": tax_setting.economic_code,
        "invoice_code": document.get("code"),
        "invoice_id": document.get("id"),
        "document_type": document.get("document_type"),
        "document_date": document.get("document_date"),
        "currency_code": document.get("currency_code") or "IRR",
        "sandbox": bool(tax_setting.sandbox_mode),
    }

    lines: List[Dict[str, Any]] = []
    for line in document.get("product_lines") or []:
        info = line.get("extra_info") or {}
        tax_snapshot = info.get("tax_snapshot") or {}
        lines.append(
            {
                "line_id": line.get("id"),
                "product_id": line.get("product_id"),
                "product_name": line.get("product_name"),
                "quantity": _to_float(line.get("quantity")),
                "unit_price": _to_float(info.get("unit_price")),
                "discount": _to_float(info.get("line_discount")),
                "tax_amount": _to_float(info.get("tax_amount")),
                "line_total": _to_float(info.get("line_total")),
                "tax_code": tax_snapshot.get("tax_code"),
                "tax_unit_id": tax_snapshot.get("tax_unit_id"),
                "tax_unit_code": tax_snapshot.get("tax_unit_code"),
                "tax_unit_name": tax_snapshot.get("tax_unit_name"),
                "product_main_unit": tax_snapshot.get("product_main_unit"),
            }
        )

    payments: List[Dict[str, Any]] = []
    for entry in document.get("account_lines") or []:
        amount = _to_float(entry.get("debit")) or _to_float(entry.get("credit"))
        if not amount:
            continue
        payments.append(
            {
                "account_id": entry.get("account_id"),
                "account_code": entry.get("account_code"),
                "account_name": entry.get("account_name"),
                "amount": amount,
                "description": entry.get("description"),
            }
        )

    counterparty = {
        "person_id": extra.get("person_id"),
        "name": person_snapshot.get("name"),
        "national_id": person_snapshot.get("national_id"),
        "economic_code": person_snapshot.get("economic_code"),
        "address": person_snapshot.get("address"),
        "postal_code": person_snapshot.get("postal_code"),
        "phone": person_snapshot.get("phone"),
    }

    return {
        "header": header,
        "lines": lines,
        "payments": payments,
        "totals": {
            "gross": _to_float(totals.get("gross")),
            "discount": _to_float(totals.get("discount")),
            "tax": _to_float(totals.get("tax")),
            "net": _to_float(totals.get("net")),
        },
        "counterparty": counterparty,
        "metadata": {
            "document_id": document.get("id"),
            "document_code": document.get("code"),
        },
    }


def _to_float(value: Any) -> float | None:
    try:
        if value is None:
            return None
        return float(value)
    except Exception:
        return None

