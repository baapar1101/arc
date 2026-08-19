"""نرمال‌سازی payload ابزارهای نوشتنی AI به قرارداد سرویس حسابیکس."""
from __future__ import annotations

from datetime import date
from typing import Any, Dict, List, Optional

_LINE_ROOT_TO_EXTRA = (
    "unit_price",
    "line_discount",
    "discount_amount",
    "discount_percent",
    "tax_amount",
    "tax_percent",
    "warehouse_id",
    "line_total",
)

CREATE_INVOICE_PARAMETERS_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "invoice_type": {
            "type": "string",
            "enum": [
                "invoice_sales",
                "invoice_purchase",
                "invoice_sales_return",
                "invoice_purchase_return",
            ],
            "description": (
                "نوع فاکتور. فقط همین مقادیر: invoice_sales (فروش)، "
                "invoice_purchase (خرید)، invoice_sales_return، invoice_purchase_return. "
                "نه sale و نه فروش."
            ),
        },
        "document_date": {
            "type": "string",
            "format": "date",
            "description": (
                "تاریخ فاکتور. ISO میلادی YYYY-MM-DD یا شمسی YYYY/MM/DD. "
                "اگر خالی بماند، امروز گذاشته می‌شود."
            ),
        },
        "currency_id": {
            "type": "integer",
            "description": (
                "شناسه ارز. اگر نمی‌دانی با list_currencies بگیر. "
                "اگر نفرستی، ارز پیش‌فرض کسب‌وکار استفاده می‌شود."
            ),
        },
        "person_id": {
            "type": "integer",
            "description": (
                "شناسه عددی مشتری/تامین‌کننده از search_persons (فیلد id). "
                "برای فروش و خرید اجباری است. نام شخص را اینجا نگذار."
            ),
        },
        "description": {
            "type": "string",
            "description": "شرح فاکتور (اختیاری)",
        },
        "is_proforma": {
            "type": "boolean",
            "description": "اگر true باشد پیش‌فاکتور ثبت می‌شود (اختیاری)",
        },
        "warehouse_id": {
            "type": "integer",
            "description": (
                "شناسه انبار پیش‌فرض سند. از list_warehouses. "
                "برای کالای انبارداری اگر انبار پیش‌فرض کسب‌وکار نباشد لازم است."
            ),
        },
        "lines": {
            "type": "array",
            "description": (
                "اقلام فاکتور. حداقل یک سطر. "
                "product_id از search_products (فیلد id). "
                "قیمت واحد را در همین سطر با unit_price بفرست — سیستم به extra_info منتقل می‌کند."
            ),
            "items": {
                "type": "object",
                "properties": {
                    "product_id": {
                        "type": "integer",
                        "description": "شناسه کالا/خدمت از search_products",
                    },
                    "quantity": {
                        "type": "number",
                        "description": "تعداد (بزرگتر از صفر)",
                    },
                    "unit_price": {
                        "type": "number",
                        "description": "قیمت واحد به ارز فاکتور (صفر یا مثبت)",
                    },
                    "description": {
                        "type": "string",
                        "description": "شرح سطر (اختیاری)",
                    },
                    "warehouse_id": {
                        "type": "integer",
                        "description": "انبار این سطر (اختیاری؛ وگرنه warehouse_id هدر)",
                    },
                    "discount_amount": {
                        "type": "number",
                        "description": "مبلغ تخفیف سطر (اختیاری)",
                    },
                    "tax_percent": {
                        "type": "number",
                        "description": "درصد مالیات سطر (اختیاری)",
                    },
                },
                "required": ["product_id", "quantity", "unit_price"],
            },
        },
    },
    "required": [
        "invoice_type",
        "person_id",
        "lines",
    ],
}

CREATE_INVOICE_DESCRIPTION = (
    "ثبت فاکتور فروش/خرید. قبل از صدا زدن: "
    "1) search_persons برای person_id، "
    "2) search_products برای product_id و قیمت، "
    "3) در صورت نیاز list_currencies برای currency_id. "
    "invoice_type باید invoice_sales یا invoice_purchase باشد. "
    "همهٔ شناسه‌ها عددی‌اند. نیاز به تأیید کاربر."
)


def coerce_positive_int(value: Any) -> Optional[int]:
    if value is None or value == "":
        return None
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return None
    return parsed if parsed > 0 else None


def coerce_number(value: Any) -> Optional[float]:
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _as_dict(value: Any) -> Dict[str, Any]:
    return dict(value) if isinstance(value, dict) else {}


def normalize_ai_invoice_line(line: Any) -> Dict[str, Any]:
    """unit_price و انبار ریشهٔ سطر را به extra_info ببر (قرارداد create_invoice)."""
    if not isinstance(line, dict):
        raise ValueError("هر سطر فاکتور باید object باشد")
    out = dict(line)
    extra = _as_dict(out.get("extra_info"))
    for key in _LINE_ROOT_TO_EXTRA:
        raw = out.get(key)
        if raw is not None and extra.get(key) is None:
            extra[key] = raw
    if extra.get("line_discount") is None and extra.get("discount_amount") is not None:
        extra["line_discount"] = extra["discount_amount"]
    product_id = coerce_positive_int(out.get("product_id"))
    if product_id is None:
        raise ValueError("هر سطر فاکتور به product_id عددی نیاز دارد. از search_products بگیر.")
    qty = coerce_number(out.get("quantity"))
    if qty is None or qty <= 0:
        raise ValueError("هر سطر فاکتور به quantity بزرگتر از صفر نیاز دارد.")
    out["product_id"] = product_id
    out["quantity"] = qty
    out["extra_info"] = extra
    return out


def _person_id_from_args(args: Dict[str, Any]) -> Optional[int]:
    extra = _as_dict(args.get("extra_info"))
    for candidate in (
        args.get("person_id"),
        args.get("customer_id"),
        args.get("supplier_id"),
        extra.get("person_id"),
        extra.get("customer_id"),
    ):
        parsed = coerce_positive_int(candidate)
        if parsed:
            return parsed
    return None


def _default_currency_id(db: Any, business_id: Any) -> Optional[int]:
    bid = coerce_positive_int(business_id)
    if not bid or db is None:
        return None
    try:
        from adapters.db.models.business import Business

        biz = db.query(Business).filter(Business.id == bid).first()
        return coerce_positive_int(getattr(biz, "default_currency_id", None) if biz else None)
    except Exception:
        return None


def build_create_invoice_payload(
    args: Dict[str, Any],
    *,
    db: Any = None,
    business_id: Any = None,
) -> Dict[str, Any]:
    """بدنهٔ create_invoice از آرگومان مدل — هم‌تراز قرارداد سرویس."""
    raw = dict(args or {})
    extra = _as_dict(raw.get("extra_info"))
    person_id = _person_id_from_args(raw)
    if person_id:
        extra["person_id"] = person_id

    warehouse_id = coerce_positive_int(raw.get("warehouse_id") or extra.get("warehouse_id"))
    if warehouse_id:
        extra["warehouse_id"] = warehouse_id

    if raw.get("is_proforma") is not None:
        extra.setdefault("is_proforma", bool(raw.get("is_proforma")))

    lines_in = raw.get("lines") or raw.get("items") or []
    if not isinstance(lines_in, list) or not lines_in:
        raise ValueError("lines الزامی است و باید حداقل یک قلم کالا داشته باشد.")
    lines: List[Dict[str, Any]] = [normalize_ai_invoice_line(item) for item in lines_in]

    invoice_type = str(raw.get("invoice_type") or raw.get("type") or "").strip()
    type_aliases = {
        "sale": "invoice_sales",
        "sales": "invoice_sales",
        "فروش": "invoice_sales",
        "purchase": "invoice_purchase",
        "buy": "invoice_purchase",
        "خرید": "invoice_purchase",
        "sale_return": "invoice_sales_return",
        "purchase_return": "invoice_purchase_return",
    }
    invoice_type = type_aliases.get(invoice_type, invoice_type)

    currency_id = coerce_positive_int(raw.get("currency_id")) or _default_currency_id(
        db, business_id or raw.get("business_id")
    )
    document_date = raw.get("document_date") or raw.get("invoice_date")
    if not document_date:
        document_date = date.today().isoformat()

    payload: Dict[str, Any] = {
        "invoice_type": invoice_type,
        "document_date": document_date,
        "currency_id": currency_id,
        "person_id": person_id,
        "description": raw.get("description"),
        "lines": lines,
        "extra_info": extra,
    }
    if raw.get("is_proforma") is not None:
        payload["is_proforma"] = bool(raw.get("is_proforma"))
    return payload


def annotate_schema_descriptions(
    schema: Dict[str, Any],
    descriptions: Dict[str, str],
) -> Dict[str, Any]:
    """توضیح فارسی به propertyهایی که description ندارند اضافه می‌کند."""
    props = schema.get("properties")
    if not isinstance(props, dict):
        return schema
    for key, text in descriptions.items():
        spec = props.get(key)
        if isinstance(spec, dict) and not (spec.get("description") or "").strip():
            props[key] = {**spec, "description": text}
    return schema
