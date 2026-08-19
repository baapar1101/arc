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


INVOICE_LINE_ITEM_SCHEMA: Dict[str, Any] = CREATE_INVOICE_PARAMETERS_SCHEMA["properties"]["lines"]["items"]

UPDATE_INVOICE_PARAMETERS_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "invoice_id": {
            "type": "integer",
            "description": "شناسه سند فاکتور از search_invoices / get_invoice_details",
        },
        "document_date": CREATE_INVOICE_PARAMETERS_SCHEMA["properties"]["document_date"],
        "currency_id": CREATE_INVOICE_PARAMETERS_SCHEMA["properties"]["currency_id"],
        "person_id": CREATE_INVOICE_PARAMETERS_SCHEMA["properties"]["person_id"],
        "description": {"type": "string", "description": "شرح فاکتور (اختیاری)"},
        "is_proforma": {"type": "boolean", "description": "پیش‌فاکتور (اختیاری)"},
        "project_id": {"type": "integer", "description": "شناسه پروژه (اختیاری)"},
        "warehouse_id": CREATE_INVOICE_PARAMETERS_SCHEMA["properties"]["warehouse_id"],
        "lines": {
            "type": "array",
            "description": (
                "اقلام کامل فاکتور. اگر نفرستی، سطرهای فعلی حفظ می‌شوند. "
                "اگر بفرستی جایگزین کل اقلام می‌شود. unit_price در ریشهٔ هر سطر."
            ),
            "items": INVOICE_LINE_ITEM_SCHEMA,
        },
    },
    "required": ["invoice_id"],
}

UPDATE_INVOICE_DESCRIPTION = (
    "ویرایش فاکتور موجود. اول get_invoice_details. "
    "اگر فقط تاریخ/شرح/شخص عوض می‌شود lines را نفرست تا اقلام فعلی بماند. "
    "اگر اقلام را می‌فرستی باید کامل باشد. نیاز به تأیید."
)


def load_existing_invoice_lines(db: Any, invoice_id: int) -> List[Dict[str, Any]]:
    from adapters.db.models.invoice_item_line import InvoiceItemLine

    rows = (
        db.query(InvoiceItemLine)
        .filter(InvoiceItemLine.document_id == int(invoice_id))
        .all()
    )
    out: List[Dict[str, Any]] = []
    for row in rows:
        extra = _as_dict(getattr(row, "extra_info", None))
        line = {
            "product_id": getattr(row, "product_id", None),
            "quantity": getattr(row, "quantity", None),
            "description": getattr(row, "description", None),
            "extra_info": extra,
        }
        if extra.get("unit_price") is not None:
            line["unit_price"] = extra["unit_price"]
        out.append(normalize_ai_invoice_line(line))
    return out


def build_update_invoice_payload(
    args: Dict[str, Any],
    *,
    db: Any = None,
    invoice_id: Any = None,
) -> Dict[str, Any]:
    """بدنهٔ update_invoice؛ اگر lines نباشد از سند فعلی پر می‌شود."""
    raw = dict(args or {})
    iid = coerce_positive_int(invoice_id or raw.get("invoice_id"))
    extra = _as_dict(raw.get("extra_info"))
    person_id = _person_id_from_args(raw)
    if person_id:
        extra["person_id"] = person_id
    warehouse_id = coerce_positive_int(raw.get("warehouse_id") or extra.get("warehouse_id"))
    if warehouse_id:
        extra["warehouse_id"] = warehouse_id
    if raw.get("is_proforma") is not None:
        extra.setdefault("is_proforma", bool(raw.get("is_proforma")))

    payload: Dict[str, Any] = {}
    for key in ("document_date", "currency_id", "description", "is_proforma", "project_id"):
        if key in raw and raw[key] is not None:
            payload[key] = raw[key]
    if person_id:
        payload["person_id"] = person_id
    if extra:
        payload["extra_info"] = extra

    lines_in = raw.get("lines") if "lines" in raw else raw.get("items")
    if isinstance(lines_in, list) and lines_in:
        payload["lines"] = [normalize_ai_invoice_line(item) for item in lines_in]
    elif db is not None and iid:
        existing = load_existing_invoice_lines(db, iid)
        if not existing:
            raise ValueError(
                "این فاکتور سطری ندارد. برای ویرایش اقلام، lines را با product_id و unit_price بفرست."
            )
        payload["lines"] = existing
    else:
        raise ValueError(
            "برای ویرایش فاکتور invoice_id لازم است؛ اگر اقلام را عوض نمی‌کنی همان id کافی است."
        )
    return payload


_CHECK_TYPE_ALIASES = {
    "received": "received",
    "دریافتی": "received",
    "دریافت": "received",
    "in": "received",
    "transferred": "transferred",
    "پرداختی": "transferred",
    "پرداخت": "transferred",
    "issued": "transferred",
    "out": "transferred",
}

CREATE_CHECK_PARAMETERS_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "type": {
            "type": "string",
            "enum": ["received", "transferred"],
            "description": "received=چک دریافتی (person_id اجباری)، transferred=چک پرداختی",
        },
        "check_number": {"type": "string", "description": "شماره چک"},
        "amount": {"type": "number", "description": "مبلغ (بزرگتر از صفر)"},
        "issue_date": {"type": "string", "format": "date", "description": "تاریخ صدور"},
        "due_date": {"type": "string", "format": "date", "description": "تاریخ سررسید (>= صدور)"},
        "person_id": {
            "type": "integer",
            "description": "شناسه شخص از search_persons. برای چک دریافتی اجباری است.",
        },
        "currency_id": {
            "type": "integer",
            "description": "شناسه ارز از list_currencies؛ اگر خالی باشد ارز پیش‌فرض کسب‌وکار",
        },
        "bank_name": {"type": "string", "description": "نام بانک (اختیاری)"},
        "branch_name": {"type": "string", "description": "شعبه (اختیاری)"},
        "sayad_code": {"type": "string", "description": "شناسه صیاد ۱۶ رقمی (اختیاری)"},
    },
    "required": ["type", "check_number", "amount", "issue_date", "due_date"],
}


def build_create_check_payload(
    args: Dict[str, Any],
    *,
    db: Any = None,
    business_id: Any = None,
) -> Dict[str, Any]:
    raw = dict(args or {})
    ctype = str(raw.get("type") or "").strip()
    ctype = _CHECK_TYPE_ALIASES.get(ctype, ctype.lower())
    if ctype not in ("received", "transferred"):
        raise ValueError("type باید received یا transferred باشد.")
    person_id = _person_id_from_args(raw)
    if ctype == "received" and not person_id:
        raise ValueError("برای چک دریافتی person_id الزامی است. از search_persons بگیر.")
    amount = coerce_number(raw.get("amount"))
    if amount is None or amount <= 0:
        raise ValueError("amount باید عدد بزرگتر از صفر باشد.")
    currency_id = coerce_positive_int(raw.get("currency_id")) or _default_currency_id(
        db, business_id or raw.get("business_id")
    )
    if not currency_id:
        raise ValueError("currency_id مشخص نیست. list_currencies را صدا بزن.")
    return {
        "type": ctype,
        "check_number": str(raw.get("check_number") or "").strip(),
        "amount": amount,
        "issue_date": raw.get("issue_date"),
        "due_date": raw.get("due_date"),
        "person_id": person_id,
        "currency_id": currency_id,
        "bank_name": raw.get("bank_name"),
        "branch_name": raw.get("branch_name"),
        "sayad_code": raw.get("sayad_code"),
        "document_date": raw.get("document_date") or raw.get("issue_date"),
    }


_ACCOUNT_KIND_ALIASES = {
    "bank": "bank",
    "بانک": "bank",
    "cash": "cash_register",
    "cash_register": "cash_register",
    "صندوق": "cash_register",
    "petty_cash": "petty_cash",
    "تنخواه": "petty_cash",
    "تنخواهگردان": "petty_cash",
}


def _account_kind(value: Any) -> str:
    return _ACCOUNT_KIND_ALIASES.get(str(value or "").strip().lower(), str(value or "").strip())


def build_create_transfer_payload(
    args: Dict[str, Any],
    *,
    db: Any = None,
    business_id: Any = None,
) -> Dict[str, Any]:
    raw = dict(args or {})
    src = raw.get("source") if isinstance(raw.get("source"), dict) else {}
    dst = raw.get("destination") if isinstance(raw.get("destination"), dict) else {}
    from_type = _account_kind(raw.get("from_account_type") or src.get("type"))
    to_type = _account_kind(raw.get("to_account_type") or dst.get("type"))
    from_id = coerce_positive_int(raw.get("from_account_id") or src.get("id"))
    to_id = coerce_positive_int(raw.get("to_account_id") or dst.get("id"))
    if from_type not in ("bank", "cash_register", "petty_cash"):
        raise ValueError("from_account_type باید bank یا cash_register یا petty_cash باشد.")
    if to_type not in ("bank", "cash_register", "petty_cash"):
        raise ValueError("to_account_type باید bank یا cash_register یا petty_cash باشد.")
    if not from_id or not to_id:
        raise ValueError(
            "from_account_id و to_account_id الزامی است. از list_bank_accounts / "
            "list_cash_registers / list_petty_cash بگیر."
        )
    amount = coerce_number(raw.get("amount"))
    if amount is None or amount <= 0:
        raise ValueError("amount باید بزرگتر از صفر باشد.")
    currency_id = coerce_positive_int(raw.get("currency_id")) or _default_currency_id(
        db, business_id or raw.get("business_id")
    )
    if not currency_id:
        raise ValueError("currency_id مشخص نیست. list_currencies را صدا بزن.")
    return {
        "document_date": raw.get("document_date") or date.today().isoformat(),
        "currency_id": currency_id,
        "amount": amount,
        "description": raw.get("description"),
        "source": {"type": from_type, "id": from_id},
        "destination": {"type": to_type, "id": to_id},
    }


_RECEIPT_TYPE_ALIASES = {
    "receipt": "receipt",
    "دریافت": "receipt",
    "payment": "payment",
    "پرداخت": "payment",
}

CREATE_RECEIPT_PAYMENT_PARAMETERS_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "type": {
            "type": "string",
            "enum": ["receipt", "payment"],
            "description": "receipt=دریافت از شخص، payment=پرداخت به شخص. نه دریافت به‌صورت آزاد.",
        },
        "document_date": {
            "type": "string",
            "format": "date",
            "description": "تاریخ سند؛ اگر خالی بماند امروز",
        },
        "currency_id": {
            "type": "integer",
            "description": "شناسه ارز از list_currencies؛ اگر خالی باشد ارز پیش‌فرض",
        },
        "person_id": {
            "type": "integer",
            "description": "شناسه عددی شخص از search_persons (فیلد id)",
        },
        "amount": {"type": "number", "description": "مبلغ (بزرگتر از صفر)"},
        "account_type": {
            "type": "string",
            "enum": ["bank", "cash_register", "petty_cash"],
            "description": (
                "نوع حساب نقدی طرف. bank از list_bank_accounts، "
                "cash_register از list_cash_registers، petty_cash از list_petty_cash. "
                "این id کدینگ حساب کل نیست."
            ),
        },
        "account_id": {
            "type": "integer",
            "description": "شناسه بانک/صندوق/تنخواه مطابق account_type — نه account کدینگ",
        },
        "description": {"type": "string", "description": "شرح سند (اختیاری)"},
    },
    "required": ["type", "person_id", "amount", "account_type", "account_id"],
}


def build_create_receipt_payment_payload(
    args: Dict[str, Any],
    *,
    db: Any = None,
    business_id: Any = None,
) -> Dict[str, Any]:
    raw = dict(args or {})
    dtype = str(raw.get("type") or raw.get("document_type") or "").strip()
    dtype = _RECEIPT_TYPE_ALIASES.get(dtype, dtype.lower())
    if dtype not in ("receipt", "payment"):
        raise ValueError("type باید receipt یا payment باشد.")
    person_id = _person_id_from_args(raw)
    amount = coerce_number(raw.get("amount"))
    account_type = _account_kind(raw.get("account_type") or raw.get("transaction_type"))
    account_id = coerce_positive_int(
        raw.get("account_id")
        or raw.get("bank_id")
        or raw.get("cash_register_id")
        or raw.get("petty_cash_id")
    )
    person_lines = raw.get("person_lines") if isinstance(raw.get("person_lines"), list) else []
    account_lines = raw.get("account_lines") if isinstance(raw.get("account_lines"), list) else []
    desc = raw.get("description") or ""
    if not person_lines:
        if not person_id or amount is None or amount <= 0:
            raise ValueError("person_id و amount الزامی است. person_id را از search_persons بگیر.")
        person_lines = [{"person_id": person_id, "amount": amount, "description": desc}]
    if not account_lines:
        if amount is None or amount <= 0:
            raise ValueError("amount باید بزرگتر از صفر باشد.")
        if account_type not in ("bank", "cash_register", "petty_cash") or not account_id:
            raise ValueError(
                "account_type و account_id الزامی است. "
                "id را از list_bank_accounts / list_cash_registers / list_petty_cash بگیر نه از list_accounts."
            )
        line: Dict[str, Any] = {
            "amount": amount,
            "description": desc,
            "transaction_type": account_type,
        }
        if account_type == "bank":
            line["bank_id"] = account_id
        elif account_type == "cash_register":
            line["cash_register_id"] = account_id
        else:
            line["petty_cash_id"] = account_id
        account_lines = [line]
    currency_id = coerce_positive_int(raw.get("currency_id")) or _default_currency_id(
        db, business_id or raw.get("business_id")
    )
    if not currency_id:
        raise ValueError("currency_id مشخص نیست. list_currencies را صدا بزن.")
    return {
        "document_type": dtype,
        "document_date": raw.get("document_date") or date.today().isoformat(),
        "currency_id": currency_id,
        "description": desc,
        "person_lines": person_lines,
        "account_lines": account_lines,
        "extra_info": _as_dict(raw.get("extra_info")),
    }


_WH_DOC_TYPE_ALIASES = {
    "receipt": "receipt",
    "ورود": "receipt",
    "in": "receipt",
    "issue": "issue",
    "خروج": "issue",
    "out": "issue",
    "transfer": "transfer",
    "انتقال": "transfer",
    "adjustment": "adjustment",
    "تعدیل": "adjustment",
    "production_in": "production_in",
    "production_out": "production_out",
}

CREATE_WAREHOUSE_DOCUMENT_PARAMETERS_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "doc_type": {
            "type": "string",
            "enum": ["receipt", "issue", "transfer", "adjustment", "production_in", "production_out"],
            "description": (
                "نوع حواله دستی. receipt=ورود، issue=خروج، transfer=انتقال بین انبار، "
                "adjustment=تعدیل. این ابزار حوالهٔ مستقل است نه فاکتور."
            ),
        },
        "document_date": {
            "type": "string",
            "format": "date",
            "description": "تاریخ حواله؛ اگر خالی بماند امروز",
        },
        "warehouse_id": {
            "type": "integer",
            "description": "انبار واحد (ورود=مقصد، خروج=مبدأ). از list_warehouses",
        },
        "warehouse_id_from": {
            "type": "integer",
            "description": "انبار مبدأ — برای خروج و انتقال لازم است",
        },
        "warehouse_id_to": {
            "type": "integer",
            "description": "انبار مقصد — برای ورود و انتقال لازم است",
        },
        "description": {"type": "string", "description": "شرح حواله (اختیاری)"},
        "lines": {
            "type": "array",
            "description": "اقلام حواله. product_id از search_products، quantity > 0",
            "items": {
                "type": "object",
                "properties": {
                    "product_id": {"type": "integer", "description": "شناسه کالا از search_products"},
                    "quantity": {"type": "number", "description": "تعداد مثبت"},
                    "description": {"type": "string", "description": "شرح سطر (اختیاری)"},
                },
                "required": ["product_id", "quantity"],
            },
        },
    },
    "required": ["doc_type", "lines"],
}

CREATE_WAREHOUSE_DOCUMENT_DESCRIPTION = (
    "ثبت حواله انبار دستی (ورود/خروج/انتقال). قبل از صدا: "
    "list_warehouses برای شناسه انبار، search_products برای product_id. "
    "برای ورود warehouse_id یا warehouse_id_to؛ برای خروج warehouse_id یا warehouse_id_from. "
    "نیاز به تأیید. حواله در وضعیت پیش‌نویس ساخته می‌شود."
)


def build_create_warehouse_document_payload(args: Dict[str, Any]) -> Dict[str, Any]:
    raw = dict(args or {})
    doc_type = str(raw.get("doc_type") or raw.get("type") or "").strip()
    doc_type = _WH_DOC_TYPE_ALIASES.get(doc_type, doc_type.lower())
    allowed = ("receipt", "issue", "transfer", "adjustment", "production_in", "production_out")
    if doc_type not in allowed:
        raise ValueError(
            "doc_type باید یکی از receipt/issue/transfer/adjustment باشد."
        )
    lines_in = raw.get("lines") or raw.get("items") or []
    if not isinstance(lines_in, list) or not lines_in:
        raise ValueError("lines الزامی است؛ هر سطر product_id و quantity دارد.")
    lines: List[Dict[str, Any]] = []
    for item in lines_in:
        if not isinstance(item, dict):
            raise ValueError("هر سطر حواله باید object باشد.")
        pid = coerce_positive_int(item.get("product_id"))
        qty = coerce_number(item.get("quantity"))
        if not pid:
            raise ValueError("هر سطر به product_id عددی نیاز دارد. از search_products بگیر.")
        if qty is None or qty <= 0:
            raise ValueError("هر سطر به quantity بزرگتر از صفر نیاز دارد.")
        line = {"product_id": pid, "quantity": qty}
        if item.get("description"):
            line["description"] = item.get("description")
        lines.append(line)
    wid = coerce_positive_int(raw.get("warehouse_id"))
    w_from = coerce_positive_int(raw.get("warehouse_id_from"))
    w_to = coerce_positive_int(raw.get("warehouse_id_to"))
    if doc_type in ("receipt", "production_in"):
        w_to = w_to or wid
        if not w_to:
            raise ValueError("برای حواله ورود warehouse_id یا warehouse_id_to لازم است. از list_warehouses بگیر.")
    elif doc_type in ("issue", "production_out"):
        w_from = w_from or wid
        if not w_from:
            raise ValueError("برای حواله خروج warehouse_id یا warehouse_id_from لازم است. از list_warehouses بگیر.")
    elif doc_type == "transfer":
        if not w_from or not w_to:
            raise ValueError("برای انتقال، warehouse_id_from و warehouse_id_to هر دو لازم است.")
    else:
        w_to = w_to or w_from or wid
        if not w_to and not w_from:
            raise ValueError("برای تعدیل حداقل یک انبار لازم است.")
    return {
        "doc_type": doc_type,
        "document_date": raw.get("document_date") or date.today().isoformat(),
        "warehouse_id_from": w_from,
        "warehouse_id_to": w_to,
        "description": raw.get("description"),
        "lines": lines,
    }


_WORKFLOW_STATUS_ALIASES = {
    "پیش‌نویس": "پیش‌نویس",
    "draft": "پیش‌نویس",
    "فعال": "فعال",
    "active": "فعال",
    "غیرفعال": "غیرفعال",
    "inactive": "غیرفعال",
}


def normalize_workflow_graph(data: Any) -> Dict[str, Any]:
    if not isinstance(data, dict):
        raise ValueError(
            "workflow_data باید object با nodes و connections باشد. "
            "اول get_workflow_design_rules سپس list_workflow_trigger_catalog و "
            "validate_workflow_draft را صدا بزن."
        )
    nodes = data.get("nodes")
    connections = data.get("connections")
    if not isinstance(nodes, list):
        raise ValueError("workflow_data.nodes باید آرایه باشد.")
    if connections is None:
        connections = []
    if not isinstance(connections, list):
        raise ValueError("workflow_data.connections باید آرایه باشد.")
    return {**data, "nodes": nodes, "connections": connections}


def build_create_workflow_payload(args: Dict[str, Any]) -> Dict[str, Any]:
    raw = dict(args or {})
    name = str(raw.get("name") or "").strip()
    if not name:
        raise ValueError("name الزامی است.")
    data = normalize_workflow_graph(raw.get("workflow_data"))
    status = str(raw.get("status") or "پیش‌نویس").strip()
    status = _WORKFLOW_STATUS_ALIASES.get(status, status)
    return {
        "name": name,
        "description": raw.get("description"),
        "workflow_data": data,
        "status": status,
        "settings": raw.get("settings") if isinstance(raw.get("settings"), dict) else None,
    }


def build_create_expense_income_payload(
    args: Dict[str, Any],
    *,
    db: Any = None,
    business_id: Any = None,
) -> Dict[str, Any]:
    raw = dict(args or {})
    dtype = str(raw.get("document_type") or raw.get("type") or "").strip().lower()
    dtype = {"expense": "expense", "هزینه": "expense", "income": "income", "درآمد": "income"}.get(
        dtype, dtype
    )
    if dtype not in ("expense", "income"):
        raise ValueError("document_type باید expense یا income باشد.")
    amount = coerce_number(raw.get("amount"))
    if amount is None or amount <= 0:
        raise ValueError("amount باید بزرگتر از صفر باشد.")
    account_id = coerce_positive_int(raw.get("account_id"))
    if not account_id:
        raise ValueError("account_id حساب هزینه/درآمد را از list_accounts بگیر.")
    raw_cp = str(raw.get("counterparty_type") or "").strip()
    if raw_cp.lower() in ("person", "شخص"):
        cp_type = "person"
    else:
        cp_type = _account_kind(raw_cp)
    if cp_type not in ("bank", "cash_register", "petty_cash", "person"):
        raise ValueError("counterparty_type باید bank/cash_register/petty_cash/person باشد.")
    cp_id = coerce_positive_int(raw.get("counterparty_id"))
    if not cp_id:
        raise ValueError("counterparty_id الزامی است.")
    currency_id = coerce_positive_int(raw.get("currency_id")) or _default_currency_id(
        db, business_id or raw.get("business_id")
    )
    if not currency_id:
        raise ValueError("currency_id مشخص نیست. list_currencies را صدا بزن.")
    doc_date = raw.get("document_date") or date.today().isoformat()
    tx_date = raw.get("transaction_date") or f"{doc_date}T12:00:00"
    counterparty_line: Dict[str, Any] = {
        "transaction_type": cp_type,
        "amount": amount,
        "transaction_date": tx_date,
        "description": raw.get("description"),
    }
    if cp_type == "bank":
        counterparty_line["bank_id"] = cp_id
    elif cp_type == "cash_register":
        counterparty_line["cash_register_id"] = cp_id
    elif cp_type == "petty_cash":
        counterparty_line["petty_cash_id"] = cp_id
    else:
        counterparty_line["person_id"] = cp_id
    return {
        "document_type": dtype,
        "document_date": doc_date,
        "currency_id": currency_id,
        "description": raw.get("description"),
        "item_lines": [
            {
                "account_id": account_id,
                "amount": amount,
                "description": raw.get("line_description") or raw.get("description"),
            }
        ],
        "counterparty_lines": [counterparty_line],
    }
