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
    "tax_rate",
    "warehouse_id",
    "line_total",
    "discount_type",
    "discount_value",
    "unit",
    "unit_price_source",
)

_INVOICE_PERSON_TYPES = frozenset({
    "invoice_sales",
    "invoice_purchase",
    "invoice_sales_return",
    "invoice_purchase_return",
})

_INVOICE_TYPE_ALIASES = {
    "sale": "invoice_sales",
    "sales": "invoice_sales",
    "فروش": "invoice_sales",
    "فاکتور فروش": "invoice_sales",
    "purchase": "invoice_purchase",
    "buy": "invoice_purchase",
    "خرید": "invoice_purchase",
    "فاکتور خرید": "invoice_purchase",
    "sale_return": "invoice_sales_return",
    "sales_return": "invoice_sales_return",
    "برگشت از فروش": "invoice_sales_return",
    "برگشت فروش": "invoice_sales_return",
    "purchase_return": "invoice_purchase_return",
    "برگشت از خرید": "invoice_purchase_return",
    "برگشت خرید": "invoice_purchase_return",
    "waste": "invoice_waste",
    "ضایعات": "invoice_waste",
    "direct_consumption": "invoice_direct_consumption",
    "مصرف مستقیم": "invoice_direct_consumption",
    "production": "invoice_production",
    "تولید": "invoice_production",
}

_INVOICE_LINE_ITEM_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "product_id": {
            "type": "integer",
            "description": "شناسه کالا/خدمت از search_products",
        },
        "quantity": {"type": "number", "description": "تعداد (بزرگتر از صفر)"},
        "unit_price": {
            "type": "number",
            "description": "قیمت واحد به ارز فاکتور (صفر یا مثبت)",
        },
        "description": {"type": "string", "description": "شرح سطر (اختیاری)"},
        "warehouse_id": {
            "type": "integer",
            "description": "انبار این سطر (اختیاری؛ وگرنه warehouse_id هدر)",
        },
        "unit": {"type": "string", "description": "واحد سطر (اصلی یا فرعی کالا)"},
        "discount_amount": {"type": "number", "description": "مبلغ تخفیف سطر"},
        "discount_percent": {"type": "number", "description": "درصد تخفیف سطر ۰ تا ۱۰۰"},
        "discount_type": {
            "type": "string",
            "enum": ["percent", "amount"],
            "description": "نوع تخفیف سطر مثل فرم: percent یا amount",
        },
        "discount_value": {
            "type": "number",
            "description": "مقدار تخفیف مطابق discount_type",
        },
        "tax_percent": {"type": "number", "description": "درصد مالیات سطر"},
        "tax_rate": {"type": "number", "description": "معادل tax_percent"},
        "tax_amount": {"type": "number", "description": "مبلغ مالیات سطر (اختیاری)"},
        "selected_instance_ids": {
            "type": "array",
            "items": {"type": "integer"},
            "description": "شناسه نمونه‌های یونیک این سطر (کالای یونیک)",
        },
    },
    "required": ["product_id", "quantity", "unit_price"],
}

_INVOICE_PAYMENT_ITEM_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "type": {
            "type": "string",
            "enum": [
                "bank",
                "cash_register",
                "petty_cash",
                "check",
                "person",
                "account",
            ],
            "description": (
                "نوع تسویه مثل تب پرداخت فرم. "
                "bank از list_bank_accounts، cash_register از list_cash_registers، "
                "petty_cash از list_petty_cash، check از search_checks."
            ),
        },
        "amount": {"type": "number", "description": "مبلغ پرداخت (بزرگتر از صفر)"},
        "account_id": {
            "type": "integer",
            "description": "شناسه بانک/صندوق/تنخواه مطابق type",
        },
        "bank_id": {"type": "integer"},
        "cash_register_id": {"type": "integer"},
        "petty_cash_id": {"type": "integer"},
        "check_id": {"type": "integer"},
        "person_id": {"type": "integer", "description": "برای type=person"},
        "transaction_date": {"type": "string", "format": "date"},
        "description": {"type": "string"},
        "commission": {"type": "number"},
        "settles_amount": {
            "type": "number",
            "description": "مبلغ تسویه به ارز فاکتور (پرداخت بین‌ارزی)",
        },
        "fx_rate": {"type": "number"},
        "payment_currency_id": {"type": "integer"},
        "allow_large_fx_diff": {"type": "boolean"},
    },
    "required": ["type", "amount"],
}

_INVOICE_ADJUSTMENT_ITEM_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "kind": {
            "type": "string",
            "enum": ["addition", "deduction"],
            "description": "addition=اضافه، deduction=کسور",
        },
        "account_id": {
            "type": "integer",
            "description": "سرفصل از list_accounts",
        },
        "amount": {"type": "number"},
        "tax_rate": {"type": "number", "description": "درصد مالیات این ردیف"},
        "description": {"type": "string"},
    },
    "required": ["kind", "account_id", "amount"],
}

_INVOICE_WRITE_FIELDS_SCHEMA: Dict[str, Any] = {
    "invoice_type": {
        "type": "string",
        "enum": [
            "invoice_sales",
            "invoice_purchase",
            "invoice_sales_return",
            "invoice_purchase_return",
            "invoice_waste",
            "invoice_direct_consumption",
            "invoice_production",
        ],
        "description": (
            "نوع فاکتور مثل فرم. فروش/خرید و برگشت‌ها person_id می‌خواهند. "
            "معادل فارسی (فروش/خرید/ضایعات/تولید) هم پذیرفته می‌شود."
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
    "due_date": {
        "type": "string",
        "format": "date",
        "description": "تاریخ سررسید. اگر خالی باشد همان تاریخ فاکتور در extra_info ذخیره می‌شود.",
    },
    "currency_id": {
        "type": "integer",
        "description": (
            "شناسه ارز فاکتور از list_currencies. "
            "اگر نفرستی، ارز پیش‌فرض کسب‌وکار استفاده می‌شود."
        ),
    },
    "fx_rate_id": {
        "type": "integer",
        "description": "شناسه نرخ ارز دستی وقتی ارز فاکتور با ارز پایه فرق دارد",
    },
    "person_id": {
        "type": "integer",
        "description": (
            "شناسه عددی مشتری/تامین‌کننده از search_persons (فیلد id). "
            "برای فروش، خرید و برگشت‌ها اجباری است. نام شخص را اینجا نگذار."
        ),
    },
    "description": {"type": "string", "description": "عنوان/شرح فاکتور"},
    "code": {
        "type": "string",
        "description": "شماره فاکتور دستی؛ اگر خالی باشد خودکار تولید می‌شود",
    },
    "is_proforma": {
        "type": "boolean",
        "description": "true = پیش‌فاکتور. در پیش‌فاکتور payments ارسال نمی‌شود.",
    },
    "warehouse_id": {
        "type": "integer",
        "description": "انبار پیش‌فرض سند از list_warehouses",
    },
    "project_id": {
        "type": "integer",
        "description": "شناسه پروژه از search_projects",
    },
    "tag_ids": {
        "type": "array",
        "items": {"type": "integer"},
        "description": "برچسب‌های فاکتور",
    },
    "post_inventory": {
        "type": "boolean",
        "description": "صدور حواله انبار برای این فاکتور",
    },
    "auto_post_warehouse": {
        "type": "boolean",
        "description": "ثبت قطعی حواله (وگرنه حواله پیش‌نویس)",
    },
    "ignore_credit_check": {
        "type": "boolean",
        "description": "نادیده گرفتن سقف اعتبار مشتری (فروش)",
    },
    "warehouse_release_mode": {
        "type": "string",
        "enum": ["none", "draft", "posted"],
        "description": "حواله انبار: none=بدون حواله، draft=پیش‌نویس، posted=ثبت قطعی",
    },
    "seller_id": {
        "type": "integer",
        "description": "فروشنده/بازاریاب از search_persons (نوع فروشنده)",
    },
    "commission": {
        "type": "object",
        "description": "کارمزد فروشنده",
        "properties": {
            "type": {"type": "string", "enum": ["percentage", "amount"]},
            "value": {"type": "number"},
        },
    },
    "global_discount": {
        "type": "object",
        "description": "تخفیف کلی فاکتور مثل فرم",
        "properties": {
            "type": {"type": "string", "enum": ["percent", "amount"]},
            "value": {"type": "number"},
        },
    },
    "invoice_adjustments": {
        "type": "array",
        "description": "اضافات و کسورات فاکتور. سرفصل از list_accounts.",
        "items": _INVOICE_ADJUSTMENT_ITEM_SCHEMA,
    },
    "installment_plan": {
        "type": "object",
        "description": "طرح اقساط فروش (فقط فاکتور قطعی فروش/برگشت فروش)",
        "properties": {
            "down_payment": {"type": "number"},
            "num_installments": {"type": "integer"},
            "first_due_date": {"type": "string", "format": "date"},
            "period": {"type": "string", "enum": ["monthly", "days"]},
            "period_days": {"type": "integer"},
            "interest_rate": {"type": "number"},
            "schedule": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "seq": {"type": "integer"},
                        "due_date": {"type": "string", "format": "date"},
                        "principal": {"type": "number"},
                        "interest": {"type": "number"},
                        "total": {"type": "number"},
                    },
                },
            },
        },
    },
    "loyalty_redemption_points": {
        "type": "integer",
        "description": "امتیاز باشگاه مشتریان برای کسر از فاکتور فروش",
    },
    "payments": {
        "type": "array",
        "description": (
            "تسویه‌های همزمان فاکتور قطعی (تب پرداخت فرم). "
            "برای پیش‌فاکتور نفرست. در ویرایش اگر بفرستی جایگزین اسناد دریافت/پرداخت قبلی است."
        ),
        "items": _INVOICE_PAYMENT_ITEM_SCHEMA,
    },
    "lines": {
        "type": "array",
        "description": (
            "اقلام فاکتور. حداقل یک سطر در ایجاد. "
            "product_id از search_products. قیمت واحد را با unit_price بفرست."
        ),
        "items": _INVOICE_LINE_ITEM_SCHEMA,
    },
}

CREATE_INVOICE_PARAMETERS_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": dict(_INVOICE_WRITE_FIELDS_SCHEMA),
    "required": ["invoice_type", "lines"],
}

CREATE_INVOICE_DESCRIPTION = (
    "ثبت فاکتور با همان فیلدهای فرم صدور فاکتور: نوع، تاریخ، سررسید، ارز، طرف‌حساب، "
    "اقلام (قیمت/تخفیف/مالیات/انبار)، تخفیف کلی، اضافات/کسورات، فروشنده و کارمزد، "
    "اقساط، پرداخت همزمان، پروژه، برچسب، پیش‌فاکتور. "
    "قبل از صدا: search_persons، search_products، در صورت نیاز list_currencies و list_warehouses. "
    "برای فروش/خرید person_id عددی الزامی است. نیاز به تأیید."
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
    """unit_price و فیلدهای سطر فرم را به extra_info ببر (قرارداد create_invoice)."""
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
    if extra.get("tax_percent") is None and extra.get("tax_rate") is not None:
        extra["tax_percent"] = extra["tax_rate"]
    if extra.get("tax_rate") is None and extra.get("tax_percent") is not None:
        extra["tax_rate"] = extra["tax_percent"]
    instances = out.get("selected_instance_ids")
    if instances is None:
        instances = extra.get("selected_instance_ids")
    if isinstance(instances, list):
        extra["selected_instance_ids"] = [
            int(x) for x in instances if x is not None and x != ""
        ]
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


def _normalize_invoice_type(raw: Any) -> str:
    s = str(raw or "").strip()
    if not s:
        return ""
    mapped = _INVOICE_TYPE_ALIASES.get(s) or _INVOICE_TYPE_ALIASES.get(s.lower())
    return mapped or s


def _normalize_invoice_adjustments(raw: Any) -> Optional[List[Dict[str, Any]]]:
    if raw is None:
        return None
    if not isinstance(raw, list):
        raise ValueError("invoice_adjustments باید آرایه باشد.")
    out: List[Dict[str, Any]] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        account_id = coerce_positive_int(item.get("account_id"))
        amount = coerce_number(item.get("amount"))
        if not account_id or amount is None or amount <= 0:
            continue
        kind = str(item.get("kind") or "addition").strip().lower()
        if kind in ("کسور", "deduct", "discount"):
            kind = "deduction"
        elif kind in ("اضافه", "add"):
            kind = "addition"
        if kind not in ("addition", "deduction"):
            kind = "addition"
        row: Dict[str, Any] = {
            "kind": kind,
            "account_id": account_id,
            "amount": amount,
            "tax_rate": coerce_number(item.get("tax_rate")) or 0,
        }
        desc = item.get("description")
        if desc:
            row["description"] = str(desc).strip()
        out.append(row)
    return out


def _normalize_invoice_payments(raw: Any) -> Optional[List[Dict[str, Any]]]:
    if raw is None:
        return None
    if not isinstance(raw, list):
        raise ValueError("payments باید آرایه باشد.")
    out: List[Dict[str, Any]] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        amount = coerce_number(item.get("amount"))
        if amount is None or amount <= 0:
            continue
        ttype = str(
            item.get("type") or item.get("transaction_type") or item.get("account_type") or ""
        ).strip().lower()
        ttype = {
            "بانک": "bank",
            "صندوق": "cash_register",
            "تنخواه": "petty_cash",
            "چک": "check",
            "شخص": "person",
            "حساب": "account",
            "cash": "cash_register",
        }.get(ttype, ttype)
        if ttype not in ("bank", "cash_register", "petty_cash", "check", "person", "account"):
            raise ValueError(
                "type هر پرداخت باید bank، cash_register، petty_cash، check، person یا account باشد."
            )
        row: Dict[str, Any] = {
            "type": ttype,
            "transaction_type": ttype,
            "amount": amount,
        }
        account_id = coerce_positive_int(
            item.get("account_id")
            or item.get("bank_id")
            or item.get("cash_register_id")
            or item.get("petty_cash_id")
        )
        if ttype == "bank":
            row["bank_id"] = coerce_positive_int(item.get("bank_id")) or account_id
        elif ttype == "cash_register":
            row["cash_register_id"] = coerce_positive_int(item.get("cash_register_id")) or account_id
        elif ttype == "petty_cash":
            row["petty_cash_id"] = coerce_positive_int(item.get("petty_cash_id")) or account_id
        elif ttype == "check":
            cid = coerce_positive_int(item.get("check_id") or item.get("account_id"))
            if cid:
                row["check_id"] = cid
        elif ttype == "person":
            pid = coerce_positive_int(item.get("person_id") or item.get("account_id"))
            if pid:
                row["person_id"] = pid
        elif ttype == "account":
            if account_id:
                row["account_id"] = account_id
        if item.get("transaction_date"):
            row["transaction_date"] = item.get("transaction_date")
        if item.get("description"):
            row["description"] = item.get("description")
        if item.get("commission") is not None:
            row["commission"] = coerce_number(item.get("commission"))
        if item.get("settles_amount") is not None:
            row["settles_amount"] = coerce_number(item.get("settles_amount"))
        if item.get("fx_rate") is not None:
            row["fx_rate"] = coerce_number(item.get("fx_rate"))
        pay_cur = coerce_positive_int(item.get("payment_currency_id"))
        if pay_cur:
            row["payment_currency_id"] = pay_cur
        if item.get("allow_large_fx_diff") is not None:
            row["allow_large_fx_diff"] = bool(item.get("allow_large_fx_diff"))
        out.append(row)
    return out


def _apply_invoice_header_extra(raw: Dict[str, Any], extra: Dict[str, Any]) -> None:
    warehouse_id = coerce_positive_int(raw.get("warehouse_id") or extra.get("warehouse_id"))
    if warehouse_id:
        extra["warehouse_id"] = warehouse_id
    if raw.get("is_proforma") is not None:
        extra.setdefault("is_proforma", bool(raw.get("is_proforma")))
    due = raw.get("due_date") or extra.get("due_date")
    if due:
        extra["due_date"] = due
    if raw.get("post_inventory") is not None:
        extra["post_inventory"] = bool(raw.get("post_inventory"))
    if raw.get("auto_post_warehouse") is not None:
        extra["auto_post_warehouse"] = bool(raw.get("auto_post_warehouse"))
    mode = raw.get("warehouse_release_mode")
    if mode == "none":
        extra["post_inventory"] = False
        extra["auto_post_warehouse"] = False
    elif mode == "draft":
        extra["post_inventory"] = True
        extra["auto_post_warehouse"] = False
    elif mode == "posted":
        extra["post_inventory"] = True
        extra["auto_post_warehouse"] = True
    if raw.get("ignore_credit_check") is not None:
        extra["ignore_credit_check"] = bool(raw.get("ignore_credit_check"))
    seller_id = coerce_positive_int(raw.get("seller_id") or extra.get("seller_id"))
    if seller_id:
        extra["seller_id"] = seller_id
    commission = raw.get("commission") if "commission" in raw else extra.get("commission")
    if isinstance(commission, dict) and commission.get("value") is not None:
        ctype = str(commission.get("type") or "percentage").strip().lower()
        if ctype in ("percent", "percentage", "درصد"):
            ctype = "percentage"
        elif ctype in ("amount", "مبلغ"):
            ctype = "amount"
        extra["commission"] = {"type": ctype, "value": coerce_number(commission.get("value"))}
    gd = raw.get("global_discount") if "global_discount" in raw else extra.get("global_discount")
    if isinstance(gd, dict) and gd.get("value") is not None:
        gtype = str(gd.get("type") or "percent").strip().lower()
        if gtype in ("درصد", "percentage"):
            gtype = "percent"
        elif gtype in ("مبلغ",):
            gtype = "amount"
        extra["global_discount"] = {"type": gtype, "value": coerce_number(gd.get("value"))}
    elif raw.get("global_discount") is None and "global_discount" in raw:
        extra.pop("global_discount", None)
    adjs = raw.get("invoice_adjustments")
    if adjs is not None:
        extra["invoice_adjustments"] = _normalize_invoice_adjustments(adjs) or []
    plan = raw.get("installment_plan")
    if isinstance(plan, dict):
        extra["installment_plan"] = plan
    elif raw.get("installment_plan") is None and "installment_plan" in raw:
        extra.pop("installment_plan", None)


def build_create_invoice_payload(
    args: Dict[str, Any],
    *,
    db: Any = None,
    business_id: Any = None,
) -> Dict[str, Any]:
    """بدنهٔ create_invoice از آرگومان مدل — هم‌تراز فرم صدور فاکتور."""
    raw = dict(args or {})
    extra = _as_dict(raw.get("extra_info"))
    person_id = _person_id_from_args(raw)
    if person_id:
        extra["person_id"] = person_id

    _apply_invoice_header_extra(raw, extra)

    lines_in = raw.get("lines") or raw.get("items") or []
    if not isinstance(lines_in, list) or not lines_in:
        raise ValueError("lines الزامی است و باید حداقل یک قلم کالا داشته باشد.")
    lines: List[Dict[str, Any]] = [normalize_ai_invoice_line(item) for item in lines_in]

    invoice_type = _normalize_invoice_type(raw.get("invoice_type") or raw.get("type"))
    if invoice_type in _INVOICE_PERSON_TYPES and not person_id:
        raise ValueError(
            "person_id الزامی است. ابتدا search_persons را صدا بزن و id عددی شخص را بفرست."
        )

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
    if raw.get("due_date"):
        payload["due_date"] = raw.get("due_date")
    if raw.get("project_id") is not None:
        payload["project_id"] = coerce_positive_int(raw.get("project_id"))
    if raw.get("code"):
        payload["code"] = str(raw.get("code")).strip()
    fx_rate_id = coerce_positive_int(raw.get("fx_rate_id"))
    if fx_rate_id:
        payload["fx_rate_id"] = fx_rate_id
    if "tag_ids" in raw:
        tags = raw.get("tag_ids") or []
        payload["tag_ids"] = [int(x) for x in tags if x is not None and x != ""]
    if raw.get("loyalty_redemption_points") is not None:
        payload["loyalty_redemption_points"] = int(raw.get("loyalty_redemption_points") or 0)
    if not bool(payload.get("is_proforma")) and "payments" in raw:
        payload["payments"] = _normalize_invoice_payments(raw.get("payments")) or []
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


INVOICE_LINE_ITEM_SCHEMA: Dict[str, Any] = _INVOICE_LINE_ITEM_SCHEMA

UPDATE_INVOICE_PARAMETERS_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "invoice_id": {
            "type": "integer",
            "description": "شناسه سند فاکتور از search_invoices / get_invoice_details",
        },
        **_INVOICE_WRITE_FIELDS_SCHEMA,
        "lines": {
            "type": "array",
            "description": (
                "اقلام کامل فاکتور. اگر نفرستی، سطرهای فعلی حفظ می‌شوند. "
                "اگر بفرستی جایگزین کل اقلام می‌شود. unit_price در ریشهٔ هر سطر."
            ),
            "items": _INVOICE_LINE_ITEM_SCHEMA,
        },
    },
    "required": ["invoice_id"],
}

UPDATE_INVOICE_DESCRIPTION = (
    "ویرایش فاکتور با همان فیلدهای فرم ویرایش: تاریخ، سررسید، طرف‌حساب، اقلام، "
    "تخفیف کلی، اضافات/کسورات، فروشنده/کارمزد، اقساط، پرداخت‌ها، پروژه، برچسب، پیش‌فاکتور. "
    "اول get_invoice_details. اگر فقط تاریخ/شرح/شخص عوض می‌شود lines را نفرست. "
    "payments در صورت ارسال جایگزین تسویه‌های قبلی است. نیاز به تأیید."
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
    _apply_invoice_header_extra(raw, extra)

    payload: Dict[str, Any] = {}
    for key in ("document_date", "currency_id", "description", "is_proforma", "project_id", "code"):
        if key in raw and raw[key] is not None:
            payload[key] = raw[key]
    if raw.get("invoice_type") or raw.get("type"):
        payload["invoice_type"] = _normalize_invoice_type(raw.get("invoice_type") or raw.get("type"))
    if raw.get("due_date"):
        payload["due_date"] = raw.get("due_date")
    fx_rate_id = coerce_positive_int(raw.get("fx_rate_id"))
    if fx_rate_id:
        payload["fx_rate_id"] = fx_rate_id
    if "tag_ids" in raw:
        tags = raw.get("tag_ids") or []
        payload["tag_ids"] = [int(x) for x in tags if x is not None and x != ""]
    if raw.get("loyalty_redemption_points") is not None:
        payload["loyalty_redemption_points"] = int(raw.get("loyalty_redemption_points") or 0)
    if person_id:
        payload["person_id"] = person_id
    if extra:
        payload["extra_info"] = extra
    if "payments" in raw and not bool(raw.get("is_proforma")):
        payload["payments"] = _normalize_invoice_payments(raw.get("payments")) or []

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


_TX_TYPE_ALIASES = {
    **_ACCOUNT_KIND_ALIASES,
    "check": "check",
    "چک": "check",
    "check_expense": "check",
    "خرج چک": "check",
    "person": "person",
    "شخص": "person",
    "account": "account",
    "حساب": "account",
}


def _transaction_kind(value: Any) -> str:
    s = str(value or "").strip()
    return _TX_TYPE_ALIASES.get(s) or _TX_TYPE_ALIASES.get(s.lower()) or s.lower()


def _normalize_cash_side_line(
    item: Any,
    *,
    allow_account: bool = False,
    default_amount: Optional[float] = None,
    default_description: Optional[str] = None,
    default_transaction_date: Optional[str] = None,
) -> Dict[str, Any]:
    """سطر بانک/صندوق/تنخواه/چک/شخص (و در هزینه: حساب) مطابق فرم UI."""
    if not isinstance(item, dict):
        raise ValueError("هر سطر نقدی باید object باشد.")
    ttype = _transaction_kind(
        item.get("transaction_type") or item.get("type") or item.get("account_type")
    )
    allowed = {"bank", "cash_register", "petty_cash", "check", "person"}
    if allow_account:
        allowed.add("account")
    if ttype not in allowed:
        raise ValueError(
            "transaction_type باید bank، cash_register، petty_cash، check، person"
            + (" یا account" if allow_account else "")
            + " باشد."
        )
    amount = coerce_number(item.get("amount"))
    if amount is None:
        amount = default_amount
    if amount is None or amount <= 0:
        raise ValueError("مبلغ هر سطر باید بزرگتر از صفر باشد.")
    row: Dict[str, Any] = {
        "transaction_type": ttype,
        "amount": amount,
    }
    desc = item.get("description") or default_description
    if desc:
        row["description"] = desc
    tx_date = item.get("transaction_date") or default_transaction_date
    if tx_date:
        row["transaction_date"] = tx_date
    if item.get("commission") is not None:
        row["commission"] = coerce_number(item.get("commission"))
    generic_id = coerce_positive_int(
        item.get("account_id")
        or item.get("counterparty_id")
        or item.get("bank_id")
        or item.get("bank_account_id")
        or item.get("cash_register_id")
        or item.get("petty_cash_id")
        or item.get("check_id")
        or item.get("person_id")
    )
    if ttype == "bank":
        bank_id = coerce_positive_int(
            item.get("bank_id") or item.get("bank_account_id") or generic_id
        )
        if not bank_id:
            raise ValueError("برای بانک، bank_id را از list_bank_accounts بگیر.")
        row["bank_id"] = bank_id
        row["bank_account_id"] = bank_id
        if item.get("bank_name"):
            row["bank_name"] = item.get("bank_name")
        if item.get("bank_account_name"):
            row["bank_account_name"] = item.get("bank_account_name")
    elif ttype == "cash_register":
        cid = coerce_positive_int(item.get("cash_register_id") or generic_id)
        if not cid:
            raise ValueError("برای صندوق، cash_register_id را از list_cash_registers بگیر.")
        row["cash_register_id"] = cid
        if item.get("cash_register_name"):
            row["cash_register_name"] = item.get("cash_register_name")
    elif ttype == "petty_cash":
        pid = coerce_positive_int(item.get("petty_cash_id") or generic_id)
        if not pid:
            raise ValueError("برای تنخواه، petty_cash_id را از list_petty_cash بگیر.")
        row["petty_cash_id"] = pid
        if item.get("petty_cash_name"):
            row["petty_cash_name"] = item.get("petty_cash_name")
    elif ttype == "check":
        cid = coerce_positive_int(item.get("check_id") or generic_id)
        if not cid:
            raise ValueError("برای چک، check_id را از search_checks بگیر.")
        row["check_id"] = cid
        if item.get("check_number"):
            row["check_number"] = item.get("check_number")
    elif ttype == "person":
        pid = coerce_positive_int(item.get("person_id") or generic_id)
        if not pid:
            raise ValueError("برای شخص، person_id را از search_persons بگیر.")
        row["person_id"] = pid
        if item.get("person_name"):
            row["person_name"] = item.get("person_name")
    else:
        aid = coerce_positive_int(item.get("account_id") or generic_id)
        if not aid:
            raise ValueError("برای حساب، account_id را از list_accounts بگیر.")
        row["account_id"] = aid
        if item.get("account_name"):
            row["account_name"] = item.get("account_name")
    if item.get("settles_amount") is not None:
        row["settles_amount"] = coerce_number(item.get("settles_amount"))
    if item.get("fx_rate") is not None:
        row["fx_rate"] = coerce_number(item.get("fx_rate"))
    pay_cur = coerce_positive_int(item.get("payment_currency_id"))
    if pay_cur:
        row["payment_currency_id"] = pay_cur
    if item.get("allow_large_fx_diff") is not None:
        row["allow_large_fx_diff"] = bool(item.get("allow_large_fx_diff"))
    native_amt = item.get("account_currency_amount")
    if native_amt is not None:
        row["account_currency_amount"] = native_amt
    native_cur = coerce_positive_int(item.get("account_currency_id"))
    if native_cur:
        row["account_currency_id"] = native_cur
    return row


def _normalize_person_doc_line(item: Any) -> Dict[str, Any]:
    if not isinstance(item, dict):
        raise ValueError("هر سطر شخص باید object باشد.")
    person_id = coerce_positive_int(item.get("person_id"))
    amount = coerce_number(item.get("amount"))
    if not person_id:
        raise ValueError("هر سطر شخص به person_id از search_persons نیاز دارد.")
    if amount is None or amount <= 0:
        raise ValueError("مبلغ سطر شخص باید بزرگتر از صفر باشد.")
    row: Dict[str, Any] = {"person_id": person_id, "amount": amount}
    if item.get("person_name"):
        row["person_name"] = item.get("person_name")
    if item.get("description"):
        row["description"] = item.get("description")
    extra = _as_dict(item.get("extra_info"))
    invoice_id = coerce_positive_int(item.get("invoice_id") or extra.get("invoice_id"))
    if invoice_id:
        extra["invoice_id"] = invoice_id
        extra["link_to_invoice"] = True
        code = item.get("invoice_code") or extra.get("invoice_code")
        if code:
            extra["invoice_code"] = code
    if extra:
        row["extra_info"] = extra
    return row


def _normalize_settlements(raw: Any) -> List[Dict[str, Any]]:
    if not isinstance(raw, list):
        return []
    out: List[Dict[str, Any]] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        person_id = coerce_positive_int(item.get("person_id"))
        invoice_id = coerce_positive_int(item.get("invoice_id"))
        if not person_id or not invoice_id:
            continue
        allocations_in = item.get("allocations") or []
        allocations: List[Dict[str, Any]] = []
        if isinstance(allocations_in, dict):
            for seq, amount in allocations_in.items():
                amt = coerce_number(amount)
                try:
                    seq_i = int(seq)
                except (TypeError, ValueError):
                    continue
                if seq_i > 0 and amt is not None and amt > 0:
                    allocations.append({"seq": seq_i, "amount": amt})
        elif isinstance(allocations_in, list):
            for alloc in allocations_in:
                if not isinstance(alloc, dict):
                    continue
                seq_i = coerce_positive_int(alloc.get("seq"))
                amt = coerce_number(alloc.get("amount"))
                if seq_i and amt is not None and amt > 0:
                    allocations.append({"seq": seq_i, "amount": amt})
        if allocations:
            out.append(
                {
                    "person_id": person_id,
                    "invoice_id": invoice_id,
                    "allocations": allocations,
                }
            )
    return out


def _settlements_from_person_lines(lines: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    raw: List[Dict[str, Any]] = []
    for item in lines:
        if not isinstance(item, dict):
            continue
        invoice_id = coerce_positive_int(
            item.get("installment_invoice_id") or item.get("settlement_invoice_id")
        )
        person_id = coerce_positive_int(item.get("person_id"))
        allocations = item.get("installment_allocations") or item.get("allocations")
        if invoice_id and person_id and allocations:
            raw.append(
                {
                    "person_id": person_id,
                    "invoice_id": invoice_id,
                    "allocations": allocations,
                }
            )
    return _normalize_settlements(raw)


_CASH_SIDE_LINE_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "transaction_type": {
            "type": "string",
            "enum": ["bank", "cash_register", "petty_cash", "check", "person", "account"],
            "description": (
                "نوع طرف نقدی مثل فرم: bank از list_bank_accounts، "
                "cash_register از list_cash_registers، petty_cash از list_petty_cash، "
                "check از search_checks، person از search_persons، account از list_accounts"
            ),
        },
        "amount": {"type": "number", "description": "مبلغ سطر (بزرگتر از صفر)"},
        "transaction_date": {
            "type": "string",
            "description": "تاریخ تراکنش این سطر (اختیاری)",
        },
        "commission": {"type": "number", "description": "کارمزد سطر (اختیاری)"},
        "description": {"type": "string", "description": "شرح سطر (اختیاری)"},
        "bank_id": {"type": "integer", "description": "شناسه حساب بانکی کسب‌وکار"},
        "cash_register_id": {"type": "integer", "description": "شناسه صندوق"},
        "petty_cash_id": {"type": "integer", "description": "شناسه تنخواه"},
        "check_id": {"type": "integer", "description": "شناسه چک از search_checks"},
        "person_id": {"type": "integer", "description": "شناسه شخص اگر طرف شخص است"},
        "account_id": {"type": "integer", "description": "شناسه حساب کدینگ اگر طرف حساب است"},
        "settles_amount": {
            "type": "number",
            "description": "مبلغ تسویه به ارز طرف‌حساب در حالت بین‌ارزی",
        },
        "fx_rate": {"type": "number", "description": "نرخ تسعیر سطر (بین‌ارزی)"},
        "payment_currency_id": {
            "type": "integer",
            "description": "ارز طرف‌حساب در حالت بین‌ارزی از list_currencies",
        },
        "allow_large_fx_diff": {
            "type": "boolean",
            "description": "اجازه اختلاف زیاد نرخ تسعیر",
        },
    },
    "required": ["transaction_type", "amount"],
}

_RECEIPT_PERSON_LINE_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "person_id": {
            "type": "integer",
            "description": "شناسه شخص از search_persons",
        },
        "amount": {"type": "number", "description": "مبلغ این شخص (بزرگتر از صفر)"},
        "description": {"type": "string", "description": "شرح سطر شخص (اختیاری)"},
        "invoice_id": {
            "type": "integer",
            "description": "اتصال این دریافت/پرداخت به فاکتور از search_invoices",
        },
        "invoice_code": {"type": "string", "description": "شماره فاکتور (اختیاری)"},
        "installment_invoice_id": {
            "type": "integer",
            "description": "فاکتور اقساطی برای تخصیص (فقط دریافت)",
        },
        "installment_allocations": {
            "type": "array",
            "description": "تخصیص اقساط: [{seq, amount}]",
            "items": {
                "type": "object",
                "properties": {
                    "seq": {"type": "integer"},
                    "amount": {"type": "number"},
                },
            },
        },
    },
    "required": ["person_id", "amount"],
}

_EXPENSE_ITEM_LINE_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "account_id": {
            "type": "integer",
            "description": "شناسه سرفصل هزینه/درآمد از list_accounts",
        },
        "amount": {"type": "number", "description": "مبلغ سطر (بزرگتر از صفر)"},
        "description": {"type": "string", "description": "شرح سطر (اختیاری)"},
    },
    "required": ["account_id", "amount"],
}


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

_RECEIPT_WRITE_FIELDS_SCHEMA: Dict[str, Any] = {
    "document_date": {
        "type": "string",
        "format": "date",
        "description": "تاریخ سند؛ اگر خالی بماند امروز",
    },
    "currency_id": {
        "type": "integer",
        "description": "شناسه ارز از list_currencies؛ اگر خالی باشد ارز پیش‌فرض",
    },
    "project_id": {
        "type": "integer",
        "description": "پروژه سند از search_projects (اختیاری)",
    },
    "description": {"type": "string", "description": "شرح سند (اختیاری)"},
    "person_id": {
        "type": "integer",
        "description": "میانبر تک‌شخص: شناسه از search_persons وقتی person_lines نفرستی",
    },
    "amount": {
        "type": "number",
        "description": "میانبر تک‌مبلغ وقتی person_lines/account_lines نفرستی",
    },
    "account_type": {
        "type": "string",
        "enum": ["bank", "cash_register", "petty_cash", "check", "person"],
        "description": (
            "میانبر طرف نقدی. bank/cash_register/petty_cash از لیست بانک/صندوق/تنخواه، "
            "check از search_checks، person از search_persons — نه کدینگ list_accounts."
        ),
    },
    "account_id": {
        "type": "integer",
        "description": "میانبر شناسه طرف نقدی مطابق account_type",
    },
    "check_id": {
        "type": "integer",
        "description": "میانبر چک وقتی account_type=check",
    },
    "commission": {"type": "number", "description": "کارمزد طرف نقدی در حالت میانبر"},
    "transaction_date": {
        "type": "string",
        "description": "تاریخ تراکنش طرف نقدی در حالت میانبر",
    },
    "invoice_id": {
        "type": "integer",
        "description": "اتصال شخص میانبر به فاکتور از search_invoices",
    },
    "person_lines": {
        "type": "array",
        "description": (
            "سطرهای اشخاص مثل فرم. اگر خالی باشد از person_id+amount ساخته می‌شود. "
            "جمع مبالغ باید با account_lines برابر باشد."
        ),
        "items": _RECEIPT_PERSON_LINE_SCHEMA,
    },
    "account_lines": {
        "type": "array",
        "description": (
            "سطرهای بانک/صندوق/تنخواه/چک/شخص مثل فرم. "
            "اگر خالی باشد از account_type+account_id ساخته می‌شود."
        ),
        "items": {
            **_CASH_SIDE_LINE_SCHEMA,
            "properties": {
                k: v
                for k, v in _CASH_SIDE_LINE_SCHEMA["properties"].items()
                if k != "account_id"
            },
        },
    },
    "settlements": {
        "type": "array",
        "description": (
            "تخصیص اقساط فقط برای دریافت: "
            "[{person_id, invoice_id, allocations:[{seq, amount}]}]"
        ),
        "items": {
            "type": "object",
            "properties": {
                "person_id": {"type": "integer"},
                "invoice_id": {"type": "integer"},
                "allocations": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "seq": {"type": "integer"},
                            "amount": {"type": "number"},
                        },
                    },
                },
            },
        },
    },
}

CREATE_RECEIPT_PAYMENT_PARAMETERS_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "type": {
            "type": "string",
            "enum": ["receipt", "payment"],
            "description": "receipt=دریافت از شخص، payment=پرداخت به شخص.",
        },
        **_RECEIPT_WRITE_FIELDS_SCHEMA,
    },
    "required": ["type"],
}

CREATE_RECEIPT_PAYMENT_DESCRIPTION = (
    "ثبت دریافت یا پرداخت با همان فیلدهای فرم: چند شخص، چند طرف نقدی "
    "(بانک/صندوق/تنخواه/چک/شخص)، کارمزد، پروژه، اتصال به فاکتور، اقساط دریافت، بین‌ارزی. "
    "برای سند ساده: person_id + amount + account_type + account_id کافی است. "
    "قبل از صدا: search_persons و list_bank_accounts یا list_cash_registers. "
    "account_id کدینگ list_accounts نیست. نیاز به تأیید."
)

UPDATE_RECEIPT_PAYMENT_PARAMETERS_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "document_id": {
            "type": "integer",
            "description": "شناسه سند از search_receipts_payments",
        },
        **_RECEIPT_WRITE_FIELDS_SCHEMA,
    },
    "required": ["document_id"],
}

UPDATE_RECEIPT_PAYMENT_DESCRIPTION = (
    "ویرایش سند دریافت/پرداخت با جایگزینی کامل سطرها مثل فرم. "
    "اول search_receipts_payments. person_lines و account_lines را کامل بفرست "
    "یا همان میانبر تک‌سطر. پروژه، فاکتور، اقساط و کارمزد هم همین‌جا است. نیاز به تأیید."
)


def _build_receipt_payment_body(
    args: Dict[str, Any],
    *,
    db: Any = None,
    business_id: Any = None,
    require_type: bool = True,
) -> Dict[str, Any]:
    raw = dict(args or {})
    dtype = str(raw.get("type") or raw.get("document_type") or "").strip()
    dtype = _RECEIPT_TYPE_ALIASES.get(dtype, dtype.lower())
    if require_type and dtype not in ("receipt", "payment"):
        raise ValueError("type باید receipt یا payment باشد.")
    person_id = _person_id_from_args(raw)
    amount = coerce_number(raw.get("amount"))
    desc = raw.get("description") or ""
    raw_person_lines = raw.get("person_lines") if isinstance(raw.get("person_lines"), list) else []
    raw_account_lines = raw.get("account_lines") if isinstance(raw.get("account_lines"), list) else []
    if raw_person_lines:
        person_lines = [_normalize_person_doc_line(item) for item in raw_person_lines]
    else:
        if not person_id or amount is None or amount <= 0:
            raise ValueError(
                "person_lines یا person_id+amount الزامی است. person_id را از search_persons بگیر."
            )
        shortcut_person: Dict[str, Any] = {
            "person_id": person_id,
            "amount": amount,
            "description": desc,
        }
        if raw.get("invoice_id"):
            shortcut_person["invoice_id"] = raw.get("invoice_id")
        if raw.get("invoice_code"):
            shortcut_person["invoice_code"] = raw.get("invoice_code")
        person_lines = [_normalize_person_doc_line(shortcut_person)]
    tx_date = raw.get("transaction_date")
    if raw_account_lines:
        account_lines = [
            _normalize_cash_side_line(
                item,
                default_amount=amount,
                default_description=desc,
                default_transaction_date=tx_date,
            )
            for item in raw_account_lines
        ]
    else:
        if amount is None or amount <= 0:
            raise ValueError("amount باید بزرگتر از صفر باشد.")
        account_type = _transaction_kind(raw.get("account_type") or raw.get("transaction_type"))
        account_id = coerce_positive_int(
            raw.get("account_id")
            or raw.get("bank_id")
            or raw.get("cash_register_id")
            or raw.get("petty_cash_id")
            or raw.get("check_id")
        )
        if account_type not in ("bank", "cash_register", "petty_cash", "check", "person") or not account_id:
            raise ValueError(
                "account_lines یا account_type+account_id الزامی است. "
                "id را از list_bank_accounts / list_cash_registers / list_petty_cash / search_checks بگیر "
                "نه از list_accounts."
            )
        shortcut_account: Dict[str, Any] = {
            "transaction_type": account_type,
            "amount": amount,
            "description": desc,
            "account_id": account_id,
        }
        if raw.get("commission") is not None:
            shortcut_account["commission"] = raw.get("commission")
        if tx_date:
            shortcut_account["transaction_date"] = tx_date
        if raw.get("check_id"):
            shortcut_account["check_id"] = raw.get("check_id")
        if raw.get("settles_amount") is not None:
            shortcut_account["settles_amount"] = raw.get("settles_amount")
        if raw.get("fx_rate") is not None:
            shortcut_account["fx_rate"] = raw.get("fx_rate")
        if raw.get("payment_currency_id"):
            shortcut_account["payment_currency_id"] = raw.get("payment_currency_id")
        account_lines = [_normalize_cash_side_line(shortcut_account)]
    currency_id = coerce_positive_int(raw.get("currency_id")) or _default_currency_id(
        db, business_id or raw.get("business_id")
    )
    if not currency_id:
        raise ValueError("currency_id مشخص نیست. list_currencies را صدا بزن.")
    extra = _as_dict(raw.get("extra_info"))
    settlements = _normalize_settlements(raw.get("settlements") or extra.get("settlements"))
    if not settlements:
        settlements = _settlements_from_person_lines(
            raw_person_lines or [raw]
        )
    if settlements:
        extra["settlements"] = settlements
    payload: Dict[str, Any] = {
        "person_lines": person_lines,
        "account_lines": account_lines,
    }
    if raw.get("document_date"):
        payload["document_date"] = raw.get("document_date")
    elif require_type:
        payload["document_date"] = date.today().isoformat()
    payload["currency_id"] = currency_id
    if "description" in raw or require_type:
        payload["description"] = desc
    if extra or "extra_info" in raw or "settlements" in raw:
        payload["extra_info"] = extra or None
    if dtype in ("receipt", "payment"):
        payload["document_type"] = dtype
    if "project_id" in raw:
        payload["project_id"] = coerce_positive_int(raw.get("project_id"))
    return payload


def build_create_receipt_payment_payload(
    args: Dict[str, Any],
    *,
    db: Any = None,
    business_id: Any = None,
) -> Dict[str, Any]:
    return _build_receipt_payment_body(
        args, db=db, business_id=business_id, require_type=True
    )


def build_update_receipt_payment_payload(
    args: Dict[str, Any],
    *,
    db: Any = None,
    business_id: Any = None,
) -> Dict[str, Any]:
    payload = _build_receipt_payment_body(
        args, db=db, business_id=business_id, require_type=False
    )
    payload.pop("document_type", None)
    return payload


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


_EXPENSE_WRITE_FIELDS_SCHEMA: Dict[str, Any] = {
    "document_date": {
        "type": "string",
        "format": "date",
        "description": "تاریخ سند؛ اگر خالی بماند امروز",
    },
    "currency_id": {
        "type": "integer",
        "description": "شناسه ارز از list_currencies؛ اگر خالی باشد ارز پیش‌فرض",
    },
    "project_id": {
        "type": "integer",
        "description": "پروژه سند از search_projects (اختیاری)",
    },
    "description": {"type": "string", "description": "شرح سند (اختیاری)"},
    "account_id": {
        "type": "integer",
        "description": "میانبر تک‌سرفصل هزینه/درآمد از list_accounts وقتی item_lines نفرستی",
    },
    "amount": {
        "type": "number",
        "description": "میانبر تک‌مبلغ وقتی item_lines/counterparty_lines نفرستی",
    },
    "line_description": {
        "type": "string",
        "description": "شرح سطر حساب در حالت میانبر",
    },
    "counterparty_type": {
        "type": "string",
        "enum": ["bank", "cash_register", "petty_cash", "check", "person", "account"],
        "description": (
            "میانبر نوع طرف‌حساب. bank/cash_register/petty_cash از لیست نقد، "
            "check از search_checks، person از search_persons، account از list_accounts"
        ),
    },
    "counterparty_id": {
        "type": "integer",
        "description": "میانبر شناسه طرف‌حساب مطابق counterparty_type",
    },
    "commission": {"type": "number", "description": "کارمزد طرف‌حساب در حالت میانبر"},
    "transaction_date": {
        "type": "string",
        "description": "تاریخ تراکنش طرف‌حساب در حالت میانبر",
    },
    "item_lines": {
        "type": "array",
        "description": (
            "سطرهای سرفصل هزینه/درآمد مثل فرم. اگر خالی باشد از account_id+amount ساخته می‌شود. "
            "جمع باید با counterparty_lines برابر باشد."
        ),
        "items": _EXPENSE_ITEM_LINE_SCHEMA,
    },
    "counterparty_lines": {
        "type": "array",
        "description": (
            "سطرهای طرف‌حساب مثل فرم: بانک/صندوق/تنخواه/چک/شخص/حساب. "
            "اگر خالی باشد از counterparty_type+counterparty_id ساخته می‌شود."
        ),
        "items": _CASH_SIDE_LINE_SCHEMA,
    },
}

CREATE_EXPENSE_INCOME_PARAMETERS_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "document_type": {
            "type": "string",
            "enum": ["expense", "income"],
            "description": "expense=هزینه، income=درآمد",
        },
        **_EXPENSE_WRITE_FIELDS_SCHEMA,
    },
    "required": ["document_type"],
}

CREATE_EXPENSE_INCOME_DESCRIPTION = (
    "ثبت هزینه یا درآمد با همان فیلدهای فرم: چند سرفصل، چند طرف‌حساب "
    "(بانک/صندوق/تنخواه/چک/شخص/حساب)، کارمزد، پروژه. "
    "برای سند ساده: account_id + amount + counterparty_type + counterparty_id کافی است. "
    "قبل از صدا: list_accounts برای سرفصل و list_bank_accounts یا list_cash_registers برای طرف نقدی. "
    "این ابزار حواله کالای هزینه/درآمد انبار نیست. نیاز به تأیید."
)

UPDATE_EXPENSE_INCOME_PARAMETERS_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "document_id": {
            "type": "integer",
            "description": "شناسه سند از search_expense_income",
        },
        **_EXPENSE_WRITE_FIELDS_SCHEMA,
    },
    "required": ["document_id"],
}

UPDATE_EXPENSE_INCOME_DESCRIPTION = (
    "ویرایش سند هزینه/درآمد با جایگزینی کامل سطرها مثل فرم. "
    "اول search_expense_income. item_lines و counterparty_lines را کامل بفرست "
    "یا همان میانبر تک‌سطر. پروژه و کارمزد هم همین‌جا است. نیاز به تأیید."
)


def _normalize_expense_item_line(item: Any) -> Dict[str, Any]:
    if not isinstance(item, dict):
        raise ValueError("هر سطر حساب هزینه/درآمد باید object باشد.")
    account_id = coerce_positive_int(item.get("account_id"))
    amount = coerce_number(item.get("amount"))
    if not account_id:
        raise ValueError("هر سطر حساب به account_id از list_accounts نیاز دارد.")
    if amount is None or amount <= 0:
        raise ValueError("مبلغ سطر حساب باید بزرگتر از صفر باشد.")
    row: Dict[str, Any] = {"account_id": account_id, "amount": amount}
    if item.get("description"):
        row["description"] = item.get("description")
    return row


def _build_expense_income_body(
    args: Dict[str, Any],
    *,
    db: Any = None,
    business_id: Any = None,
    require_type: bool = True,
) -> Dict[str, Any]:
    raw = dict(args or {})
    dtype = str(raw.get("document_type") or raw.get("type") or "").strip().lower()
    dtype = {"expense": "expense", "هزینه": "expense", "income": "income", "درآمد": "income"}.get(
        dtype, dtype
    )
    if require_type and dtype not in ("expense", "income"):
        raise ValueError("document_type باید expense یا income باشد.")
    amount = coerce_number(raw.get("amount"))
    desc = raw.get("description")
    raw_items = raw.get("item_lines") if isinstance(raw.get("item_lines"), list) else []
    raw_cps = (
        raw.get("counterparty_lines")
        if isinstance(raw.get("counterparty_lines"), list)
        else []
    )
    if raw_items:
        item_lines = [_normalize_expense_item_line(item) for item in raw_items]
    else:
        account_id = coerce_positive_int(raw.get("account_id"))
        if not account_id or amount is None or amount <= 0:
            raise ValueError(
                "item_lines یا account_id+amount الزامی است. account_id را از list_accounts بگیر."
            )
        item_lines = [
            _normalize_expense_item_line(
                {
                    "account_id": account_id,
                    "amount": amount,
                    "description": raw.get("line_description") or desc,
                }
            )
        ]
    doc_date = raw.get("document_date") or (date.today().isoformat() if require_type else None)
    tx_date = raw.get("transaction_date") or (f"{doc_date}T12:00:00" if doc_date else None)
    if raw_cps:
        counterparty_lines = [
            _normalize_cash_side_line(
                item,
                allow_account=True,
                default_amount=amount,
                default_description=desc,
                default_transaction_date=tx_date,
            )
            for item in raw_cps
        ]
    else:
        raw_cp = str(raw.get("counterparty_type") or "").strip()
        cp_type = _transaction_kind(raw_cp)
        cp_id = coerce_positive_int(raw.get("counterparty_id"))
        if cp_type not in ("bank", "cash_register", "petty_cash", "check", "person", "account") or not cp_id:
            raise ValueError(
                "counterparty_lines یا counterparty_type+counterparty_id الزامی است."
            )
        if amount is None or amount <= 0:
            raise ValueError("amount باید بزرگتر از صفر باشد.")
        shortcut: Dict[str, Any] = {
            "transaction_type": cp_type,
            "amount": amount,
            "transaction_date": tx_date,
            "description": desc,
            "account_id": cp_id,
        }
        if raw.get("commission") is not None:
            shortcut["commission"] = raw.get("commission")
        if raw.get("check_id"):
            shortcut["check_id"] = raw.get("check_id")
        counterparty_lines = [
            _normalize_cash_side_line(shortcut, allow_account=True)
        ]
    currency_id = coerce_positive_int(raw.get("currency_id")) or _default_currency_id(
        db, business_id or raw.get("business_id")
    )
    if not currency_id:
        raise ValueError("currency_id مشخص نیست. list_currencies را صدا بزن.")
    payload: Dict[str, Any] = {
        "currency_id": currency_id,
        "item_lines": item_lines,
        "counterparty_lines": counterparty_lines,
    }
    if doc_date:
        payload["document_date"] = doc_date
    if "description" in raw or require_type:
        payload["description"] = desc
    if dtype in ("expense", "income"):
        payload["document_type"] = dtype
    if "project_id" in raw:
        payload["project_id"] = coerce_positive_int(raw.get("project_id"))
    extra = _as_dict(raw.get("extra_info"))
    if extra or "extra_info" in raw:
        payload["extra_info"] = extra or None
    return payload


def build_create_expense_income_payload(
    args: Dict[str, Any],
    *,
    db: Any = None,
    business_id: Any = None,
) -> Dict[str, Any]:
    return _build_expense_income_body(
        args, db=db, business_id=business_id, require_type=True
    )


def build_update_expense_income_payload(
    args: Dict[str, Any],
    *,
    db: Any = None,
    business_id: Any = None,
) -> Dict[str, Any]:
    payload = _build_expense_income_body(
        args, db=db, business_id=business_id, require_type=False
    )
    payload.pop("document_type", None)
    return payload


# --- اشخاص: هم‌تراز با فرم UI / PersonCreateRequest و PersonUpdateRequest ---

PERSON_TYPE_ENUM = (
    "customer",
    "supplier",
    "marketer",
    "employee",
    "partner",
    "seller",
    "shareholder",
)

_PERSON_TYPE_ALIASES = {
    "customer": "مشتری",
    "مشتری": "مشتری",
    "supplier": "تامین‌کننده",
    "تامین‌کننده": "تامین‌کننده",
    "تامین کننده": "تامین‌کننده",
    "تأمين‌کننده": "تامین‌کننده",
    "vendor": "تامین‌کننده",
    "marketer": "بازاریاب",
    "بازاریاب": "بازاریاب",
    "employee": "کارمند",
    "کارمند": "کارمند",
    "partner": "همکار",
    "همکار": "همکار",
    "seller": "فروشنده",
    "فروشنده": "فروشنده",
    "shareholder": "سهامدار",
    "سهامدار": "سهامدار",
}

_PERSON_SOCIAL_PLATFORMS = (
    "telegram",
    "bale",
    "rubika",
    "eitaa",
    "whatsapp",
    "instagram",
    "linkedin",
    "twitter",
    "other",
)

_PERSON_BANK_ACCOUNT_ITEM_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "bank_name": {
            "type": "string",
            "description": "نام بانک (مثلاً مهر ایران). الزامی.",
        },
        "account_number": {"type": "string", "description": "شماره حساب (اختیاری)"},
        "card_number": {
            "type": "string",
            "description": "شماره کارت بانکی شخص (اختیاری)",
        },
        "sheba_number": {"type": "string", "description": "شماره شبا (اختیاری)"},
    },
    "required": ["bank_name"],
}

_PERSON_SOCIAL_ITEM_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "platform_key": {
            "type": "string",
            "enum": list(_PERSON_SOCIAL_PLATFORMS),
            "description": "پلتفرم پیام‌رسان. برای سایر از other + custom_label استفاده کن.",
        },
        "value": {"type": "string", "description": "آیدی، لینک یا شماره"},
        "custom_label": {
            "type": "string",
            "description": "برچسب نمایش؛ برای platform_key=other الزامی است",
        },
    },
    "required": ["platform_key", "value"],
}

_PERSON_OPENING_BALANCE_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "amount": {
            "type": "number",
            "description": "مبلغ مانده. در ایجاد باید >0 باشد مگر در ویرایش با clear=true",
        },
        "balance_type": {
            "type": "string",
            "enum": ["debit", "credit"],
            "description": "debit=شخص بدهکار (دریافتنی)، credit=بستانکار (پرداختنی)",
        },
        "fiscal_year_id": {
            "type": "integer",
            "description": "سال مالی؛ اگر خالی باشد سال جاری",
        },
        "clear": {
            "type": "boolean",
            "description": "فقط در ویرایش: حذف خط مانده از سند افتتاحیه",
        },
    },
}

_PERSON_WRITE_FIELDS_SCHEMA: Dict[str, Any] = {
    "alias_name": {
        "type": "string",
        "description": "نام مستعار نمایشی. اگر خالی باشد از name ساخته می‌شود.",
    },
    "first_name": {"type": "string", "description": "نام"},
    "last_name": {"type": "string", "description": "نام خانوادگی"},
    "person_types": {
        "type": "array",
        "items": {"type": "string", "enum": list(PERSON_TYPE_ENUM)},
        "description": (
            "انواع شخص (چندانتخابی). معادل فرم UI: "
            "customer/supplier/marketer/employee/partner/seller/shareholder"
        ),
    },
    "company_name": {"type": "string", "description": "نام شرکت"},
    "name_prefix": {
        "type": "string",
        "description": "پیشوند: آقای، خانم، شرکت، دکتر، مهندس، موسسه، اداره، سازمان، بنیاد، انجمن",
    },
    "legal_entity_type": {
        "type": "string",
        "enum": ["natural", "legal"],
        "description": "natural=حقیقی، legal=حقوقی",
    },
    "payment_id": {"type": "string", "description": "شناسه پرداخت"},
    "person_group_id": {
        "type": "integer",
        "description": "شناسه گروه اشخاص از list_person_groups",
    },
    "national_id": {"type": "string", "description": "شناسه ملی / کد ملی"},
    "registration_number": {"type": "string", "description": "شماره ثبت"},
    "economic_id": {"type": "string", "description": "شناسه اقتصادی"},
    "country": {"type": "string"},
    "province": {"type": "string"},
    "city": {"type": "string"},
    "address": {"type": "string"},
    "postal_code": {"type": "string"},
    "phone": {"type": "string", "description": "تلفن ثابت"},
    "mobile": {"type": "string", "description": "موبایل"},
    "mobile_2": {"type": "string"},
    "mobile_3": {"type": "string"},
    "fax": {"type": "string"},
    "email": {"type": "string", "format": "email"},
    "website": {"type": "string"},
    "bank_accounts": {
        "type": "array",
        "description": (
            "حساب‌های بانکی روی کارت شخص (نام بانک، شماره حساب، کارت، شبا). "
            "این همان بخش فرم تعریف شخص است — نه list_bank_accounts که حساب خزانه کسب‌وکار است. "
            "ابزار جداگانه‌ای مثل create_bank_card وجود ندارد؛ همین‌جا بفرست. "
            "در ویرایش اگر ارسال شود کل لیست جایگزین می‌شود."
        ),
        "items": _PERSON_BANK_ACCOUNT_ITEM_SCHEMA,
    },
    "social_contacts": {
        "type": "array",
        "description": "راه‌های ارتباط (تلگرام و …). در ویرایش اگر ارسال شود جایگزین کامل است.",
        "items": _PERSON_SOCIAL_ITEM_SCHEMA,
    },
    "share_count": {
        "type": "integer",
        "description": "تعداد سهام؛ برای سهامدار الزامی و حداقل ۱",
    },
    "commission_sale_percent": {"type": "number", "description": "درصد پورسانت فروش (بازاریاب/فروشنده)"},
    "commission_sales_return_percent": {"type": "number"},
    "commission_sales_amount": {"type": "number"},
    "commission_sales_return_amount": {"type": "number"},
    "commission_exclude_discounts": {"type": "boolean"},
    "commission_exclude_additions_deductions": {"type": "boolean"},
    "commission_post_in_invoice_document": {"type": "boolean"},
    "credit_limit": {"type": "number", "description": "سقف اعتبار شخص"},
    "credit_check_enabled": {
        "type": "boolean",
        "description": "بررسی اعتبار. اگر نفرستی از تنظیم کسب‌وکار تبعیت می‌شود.",
    },
    "opening_balance": _PERSON_OPENING_BALANCE_SCHEMA,
}

CREATE_PERSON_DESCRIPTION = (
    "ایجاد شخص جدید با همان فیلدهای فرم تعریف شخص در رابط کاربری. "
    "name و person_type الزامی است. برای کارت/شبا/شماره حساب شخص از bank_accounts استفاده کن "
    "(نه list_bank_accounts و نه ابزار ساختگی create_bank_card). "
    "گروه را با list_person_groups بگیر. نیاز به تأیید."
)

CREATE_PERSON_PARAMETERS_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "name": {
            "type": "string",
            "description": "نام نمایشی شخص (alias_name). همان نامی که کاربر گفته را عیناً بفرست.",
        },
        "person_type": {
            "type": "string",
            "enum": list(PERSON_TYPE_ENUM),
            "description": "نوع شخص. اگر چند نوع است person_types را هم بفرست.",
        },
        "code": {
            "type": "integer",
            "description": "کد شخص؛ اگر خالی باشد خودکار تولید می‌شود",
        },
        "tax_id": {
            "type": "string",
            "description": "سازگاری قدیمی: اگر national_id خالی باشد به‌عنوان شناسه ملی استفاده می‌شود",
        },
        **_PERSON_WRITE_FIELDS_SCHEMA,
    },
    "required": ["name", "person_type"],
}

UPDATE_PERSON_DESCRIPTION = (
    "ویرایش شخص با همان فیلدهای فرم ویرایش در رابط کاربری. فقط فیلدهایی را بفرست که باید عوض شوند. "
    "bank_accounts در صورت ارسال جایگزین کامل حساب‌های بانکی شخص می‌شود. نیاز به تأیید."
)

UPDATE_PERSON_PARAMETERS_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "person_id": {"type": "integer", "description": "شناسه شخص از search_persons"},
        "name": {
            "type": "string",
            "description": "نام نمایشی جدید (alias_name). اگر خالی باشد نام عوض نمی‌شود.",
        },
        "person_type": {
            "type": "string",
            "enum": list(PERSON_TYPE_ENUM),
            "description": "نوع تکی؛ ترجیحاً person_types را بفرست",
        },
        "code": {"type": "integer", "description": "کد شخص"},
        "tax_id": {
            "type": "string",
            "description": "سازگاری قدیمی برای شناسه ملی اگر national_id نفرستی",
        },
        **_PERSON_WRITE_FIELDS_SCHEMA,
    },
    "required": ["person_id"],
}


def _blank_to_none(value: Any) -> Optional[str]:
    if value is None:
        return None
    s = str(value).strip()
    return s if s else None


def normalize_person_type_value(raw: Any) -> Optional[str]:
    if raw is None:
        return None
    key = str(raw).strip()
    if not key:
        return None
    mapped = _PERSON_TYPE_ALIASES.get(key) or _PERSON_TYPE_ALIASES.get(key.lower())
    if mapped:
        return mapped
    raise ValueError(
        "نوع شخص نامعتبر است. مقادیر مجاز: "
        + "، ".join(PERSON_TYPE_ENUM)
        + " یا معادل فارسی (مشتری، تامین‌کننده، بازاریاب، کارمند، همکار، فروشنده، سهامدار)."
    )


def normalize_person_types(args: Dict[str, Any]) -> List[str]:
    values: List[str] = []
    raw_list = args.get("person_types")
    if isinstance(raw_list, list):
        for item in raw_list:
            mapped = normalize_person_type_value(item)
            if mapped and mapped not in values:
                values.append(mapped)
    single = normalize_person_type_value(args.get("person_type")) if args.get("person_type") else None
    if single and single not in values:
        values.append(single)
    return values


def _normalize_person_bank_accounts(raw: Any) -> Optional[List[Dict[str, Any]]]:
    if raw is None:
        return None
    if not isinstance(raw, list):
        raise ValueError("bank_accounts باید آرایه باشد.")
    out: List[Dict[str, Any]] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        bank_name = _blank_to_none(
            item.get("bank_name") or item.get("bank") or item.get("name")
        )
        if not bank_name:
            continue
        out.append(
            {
                "bank_name": bank_name,
                "account_number": _blank_to_none(
                    item.get("account_number") or item.get("account")
                ),
                "card_number": _blank_to_none(
                    item.get("card_number") or item.get("card")
                ),
                "sheba_number": _blank_to_none(
                    item.get("sheba_number")
                    or item.get("sheba")
                    or item.get("iban")
                ),
            }
        )
    return out


def _normalize_person_social_contacts(raw: Any) -> Optional[List[Dict[str, Any]]]:
    if raw is None:
        return None
    if not isinstance(raw, list):
        raise ValueError("social_contacts باید آرایه باشد.")
    out: List[Dict[str, Any]] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        platform = (_blank_to_none(item.get("platform_key") or item.get("platform")) or "").lower()
        value = _blank_to_none(item.get("value"))
        if not platform or not value:
            continue
        row: Dict[str, Any] = {"platform_key": platform, "value": value}
        label = _blank_to_none(item.get("custom_label") or item.get("label"))
        if label:
            row["custom_label"] = label
        out.append(row)
    return out


def _normalize_opening_balance(raw: Any) -> Optional[Dict[str, Any]]:
    if raw is None:
        return None
    if not isinstance(raw, dict):
        raise ValueError("opening_balance باید شیء باشد.")
    payload: Dict[str, Any] = {}
    if "amount" in raw and raw.get("amount") is not None:
        payload["amount"] = float(raw["amount"])
    if raw.get("balance_type"):
        bt = str(raw["balance_type"]).strip().lower()
        aliases = {
            "debit": "debit",
            "بدهکار": "debit",
            "دریافتنی": "debit",
            "credit": "credit",
            "بستانکار": "credit",
            "پرداختنی": "credit",
        }
        mapped = aliases.get(bt)
        if not mapped:
            raise ValueError("balance_type باید debit یا credit باشد.")
        payload["balance_type"] = mapped
    if raw.get("fiscal_year_id") is not None:
        payload["fiscal_year_id"] = int(raw["fiscal_year_id"])
    if "clear" in raw:
        payload["clear"] = bool(raw["clear"])
    return payload or None


def _copy_optional_str(args: Dict[str, Any], payload: Dict[str, Any], *keys: str) -> None:
    for key in keys:
        if key in args:
            payload[key] = _blank_to_none(args.get(key))


def _copy_optional_number(args: Dict[str, Any], payload: Dict[str, Any], key: str, *, as_int: bool = False) -> None:
    if key not in args:
        return
    raw = args.get(key)
    if raw is None or raw == "":
        payload[key] = None
        return
    payload[key] = int(raw) if as_int else float(raw)


def _copy_optional_bool(args: Dict[str, Any], payload: Dict[str, Any], key: str) -> None:
    if key in args:
        payload[key] = None if args.get(key) is None else bool(args.get(key))


def _apply_person_write_fields(args: Dict[str, Any], payload: Dict[str, Any], *, for_update: bool) -> None:
    _copy_optional_str(
        args,
        payload,
        "first_name",
        "last_name",
        "company_name",
        "name_prefix",
        "legal_entity_type",
        "payment_id",
        "national_id",
        "registration_number",
        "economic_id",
        "country",
        "province",
        "city",
        "address",
        "postal_code",
        "phone",
        "mobile",
        "mobile_2",
        "mobile_3",
        "fax",
        "email",
        "website",
    )
    if "tax_id" in args and not payload.get("national_id"):
        payload["national_id"] = _blank_to_none(args.get("tax_id"))
    if "code" in args:
        _copy_optional_number(args, payload, "code", as_int=True)
    if "person_group_id" in args:
        _copy_optional_number(args, payload, "person_group_id", as_int=True)
    if "share_count" in args:
        _copy_optional_number(args, payload, "share_count", as_int=True)
    for key in (
        "commission_sale_percent",
        "commission_sales_return_percent",
        "commission_sales_amount",
        "commission_sales_return_amount",
        "credit_limit",
    ):
        _copy_optional_number(args, payload, key)
    for key in (
        "commission_exclude_discounts",
        "commission_exclude_additions_deductions",
        "commission_post_in_invoice_document",
        "credit_check_enabled",
    ):
        _copy_optional_bool(args, payload, key)
    if "bank_accounts" in args:
        payload["bank_accounts"] = _normalize_person_bank_accounts(args.get("bank_accounts")) or []
    if "social_contacts" in args:
        payload["social_contacts"] = _normalize_person_social_contacts(args.get("social_contacts")) or []
    if "opening_balance" in args:
        payload["opening_balance"] = _normalize_opening_balance(args.get("opening_balance"))
    types = normalize_person_types(args)
    if types:
        payload["person_types"] = types
    elif not for_update and args.get("person_type"):
        payload["person_types"] = normalize_person_types(args)


def build_create_person_payload(args: Dict[str, Any]) -> Dict[str, Any]:
    name = _blank_to_none(args.get("alias_name") or args.get("name"))
    if not name:
        first = _blank_to_none(args.get("first_name"))
        last = _blank_to_none(args.get("last_name"))
        name = " ".join(p for p in (first, last) if p) or None
    if not name:
        raise ValueError("name الزامی است.")
    types = normalize_person_types(args)
    if not types:
        raise ValueError(
            "person_type یا person_types الزامی است "
            "(customer، supplier، marketer، employee، partner، seller، shareholder)."
        )
    payload: Dict[str, Any] = {
        "alias_name": name,
        "person_types": types,
    }
    _apply_person_write_fields(args, payload, for_update=False)
    if "first_name" not in args and args.get("name") and not args.get("last_name"):
        payload.setdefault("first_name", name)
    payload["person_types"] = types
    return payload


def build_update_person_payload(args: Dict[str, Any]) -> Dict[str, Any]:
    payload: Dict[str, Any] = {}
    if args.get("alias_name") or args.get("name"):
        payload["alias_name"] = _blank_to_none(args.get("alias_name") or args.get("name"))
        if args.get("name") and "first_name" not in args:
            payload["first_name"] = payload["alias_name"]
    _apply_person_write_fields(args, payload, for_update=True)
    return payload


# --- کالا/خدمت: هم‌تراز با فرم UI / ProductCreateRequest و ProductUpdateRequest ---

_PRODUCT_ITEM_TYPE_ALIASES = {
    "کالا": "کالا",
    "product": "کالا",
    "goods": "کالا",
    "commodity": "کالا",
    "item": "کالا",
    "خدمت": "خدمت",
    "service": "خدمت",
}

_PRODUCT_INVENTORY_MODE_ALIASES = {
    "bulk": "bulk",
    "فله": "bulk",
    "فله‌ای": "bulk",
    "unique": "unique",
    "یونیک": "unique",
    "serial": "unique",
}

_PRODUCT_FIELD_ALIASES = {
    "price": "base_sales_price",
    "sales_price": "base_sales_price",
    "sale_price": "base_sales_price",
    "unit_price": "base_sales_price",
    "purchase_price": "base_purchase_price",
    "buy_price": "base_purchase_price",
    "unit": "main_unit",
    "warehouse_id": "default_warehouse_id",
    "type": "item_type",
    "sku": "code",
    "fx_sales_price": "sales_price_fx",
    "fx_purchase_price": "purchase_price_fx",
    "fx_currency_id": "price_fx_currency_id",
}

_PRODUCT_CATALOG_SPEC_ITEM_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "field_id": {"type": "integer", "description": "شناسه قالب مشخصات کسب‌وکار (اختیاری)"},
        "label": {"type": "string", "description": "عنوان مشخصه"},
        "value": {"type": "string", "description": "مقدار مشخصه"},
        "sort_order": {"type": "integer"},
    },
    "required": ["label"],
}

_PRODUCT_SUPPLIER_ITEM_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "person_id": {
            "type": "integer",
            "description": "شناسه شخص تأمین‌کننده از search_persons (اختیاری)",
        },
        "name": {"type": "string", "description": "نام تأمین‌کننده اگر person_id نباشد"},
        "website": {"type": "string"},
        "phone": {"type": "string"},
        "email": {"type": "string"},
        "notes": {"type": "string"},
        "is_preferred": {"type": "boolean"},
        "sort_order": {"type": "integer"},
        "social_contacts": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "platform_key": {
                        "type": "string",
                        "enum": list(_PERSON_SOCIAL_PLATFORMS),
                    },
                    "value": {"type": "string"},
                    "custom_label": {"type": "string"},
                },
                "required": ["platform_key", "value"],
            },
        },
    },
}

_PRODUCT_PRICE_LIST_ITEM_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "price_list_id": {
            "type": "integer",
            "description": "شناسه لیست قیمت از list_price_lists",
        },
        "price_list_name": {
            "type": "string",
            "description": "نام لیست (عمده/همکار/…) اگر id را نداری",
        },
        "currency_id": {
            "type": "integer",
            "description": "شناسه ارز از list_currencies",
        },
        "currency_code": {
            "type": "string",
            "description": "کد ارز مثل USD یا IRR اگر id را نداری",
        },
        "price": {"type": "number", "description": "قیمت در این لیست و این ارز"},
        "tier_name": {
            "type": "string",
            "description": "نام پله (تکی/عمده/همکار). پیش‌فرض: پیش‌فرض",
        },
        "min_qty": {
            "type": "number",
            "description": "حداقل تعداد برای این پله. پیش‌فرض ۰",
        },
    },
    "required": ["price"],
}

_PRODUCT_OPENING_BALANCE_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "quantity": {
            "type": "number",
            "description": "تعداد اولیه. در ایجاد باید >0 باشد مگر در ویرایش با clear=true",
        },
        "cost_price": {
            "type": "number",
            "description": "بهای تمام‌شده هر واحد برای ارزش‌گذاری موجودی",
        },
        "warehouse_id": {
            "type": "integer",
            "description": "انبار از list_warehouses؛ اگر خالی باشد default_warehouse_id کالا",
        },
        "fiscal_year_id": {"type": "integer", "description": "سال مالی؛ پیش‌فرض سال جاری"},
        "clear": {
            "type": "boolean",
            "description": "فقط در ویرایش: حذف خط موجودی اولیه از سند افتتاحیه",
        },
    },
}

_PRODUCT_WRITE_FIELDS_SCHEMA: Dict[str, Any] = {
    "item_type": {
        "type": "string",
        "enum": ["کالا", "خدمت"],
        "description": "کالا (انبارداری ممکن) یا خدمت. معادل product/service هم پذیرفته می‌شود.",
    },
    "code": {
        "type": "string",
        "description": "کد کالا؛ اگر خالی باشد خودکار تولید می‌شود",
    },
    "description": {"type": "string", "description": "توضیحات کالا"},
    "category_id": {
        "type": "integer",
        "description": "شناسه دسته‌بندی از search_categories",
    },
    "main_unit": {"type": "string", "description": "واحد اصلی (مثلاً عدد، کیلوگرم)"},
    "secondary_unit": {"type": "string", "description": "واحد فرعی؛ با unit_conversion_factor"},
    "unit_conversion_factor": {
        "type": "number",
        "description": "ضریب تبدیل واحد فرعی به اصلی (مثلاً ۱۲ یعنی یک بسته = ۱۲ عدد)",
    },
    "base_sales_price": {
        "type": "number",
        "description": "قیمت فروش پایه به ارز پایه کسب‌وکار",
    },
    "base_purchase_price": {
        "type": "number",
        "description": "قیمت خرید پایه به ارز پایه کسب‌وکار",
    },
    "sales_price_fx": {
        "type": "number",
        "description": "قیمت فروش به ارز دیگر (چندارزی). با price_fx_currency_id بفرست.",
    },
    "purchase_price_fx": {
        "type": "number",
        "description": "قیمت خرید به ارز دیگر (چندارزی). با price_fx_currency_id بفرست.",
    },
    "price_fx_currency_id": {
        "type": "integer",
        "description": "ارز قیمت‌های ارزی کالا از list_currencies",
    },
    "auto_update_base_from_fx": {
        "type": "boolean",
        "description": "به‌روزرسانی خودکار قیمت پایه از نرخ × قیمت ارزی",
    },
    "base_sales_note": {"type": "string", "description": "یادداشت پیش‌فرض فروش"},
    "base_purchase_note": {"type": "string", "description": "یادداشت پیش‌فرض خرید"},
    "track_inventory": {
        "type": "boolean",
        "description": "کنترل موجودی انبار. برای خدمت باید false باشد.",
    },
    "default_warehouse_id": {
        "type": "integer",
        "description": "انبار پیش‌فرض از list_warehouses",
    },
    "reorder_point": {"type": "integer", "description": "نقطه سفارش مجدد"},
    "min_order_qty": {"type": "integer", "description": "حداقل تعداد سفارش"},
    "lead_time_days": {"type": "integer", "description": "زمان تحویل به روز"},
    "inventory_mode": {
        "type": "string",
        "enum": ["bulk", "unique"],
        "description": "bulk=فله‌ای، unique=یونیک (سریال/بارکد نمونه)",
    },
    "track_serial": {"type": "boolean", "description": "ردیابی سریال برای کالای یونیک"},
    "track_barcode": {"type": "boolean", "description": "ردیابی بارکد برای کالای یونیک"},
    "is_sales_taxable": {"type": "boolean"},
    "is_purchase_taxable": {"type": "boolean"},
    "sales_tax_rate": {"type": "number", "description": "نرخ مالیات فروش (درصد ۰ تا ۱۰۰)"},
    "purchase_tax_rate": {"type": "number", "description": "نرخ مالیات خرید (درصد)"},
    "tax_type_id": {"type": "integer", "description": "شناسه نوع مالیات از get_tax_settings"},
    "tax_code": {"type": "string", "description": "کد مالیاتی محصول"},
    "tax_unit_id": {"type": "integer", "description": "شناسه واحد مالیاتی"},
    "attribute_ids": {
        "type": "array",
        "items": {"type": "integer"},
        "description": "شناسه ویژگی‌ها از list_product_attributes. در ویرایش جایگزین کامل است.",
    },
    "barcode": {"type": "string", "description": "بارکد تکی (legacy)"},
    "general_barcodes": {
        "type": "string",
        "description": "بارکدهای عمومی جدا شده با ویرگول برای اسکن و چاپ برچسب",
    },
    "image_file_id": {
        "type": "string",
        "description": "UUID فایل تصویر از قبل آپلودشده (آپلود باینری از این ابزار ممکن نیست)",
    },
    "is_active": {"type": "boolean", "description": "فعال بودن کالا"},
    "is_public_catalog": {
        "type": "boolean",
        "description": "انتشار در کاتالوگ عمومی شبکه تأمین",
    },
    "catalog_short_description": {"type": "string"},
    "catalog_expert_review": {"type": "string"},
    "catalog_specifications": {
        "type": "array",
        "description": "مشخصات فنی کاتالوگ (عنوان/مقدار)",
        "items": _PRODUCT_CATALOG_SPEC_ITEM_SCHEMA,
    },
    "catalog_brand": {"type": "string"},
    "catalog_model": {"type": "string"},
    "catalog_country_of_origin": {"type": "string"},
    "catalog_video_url": {"type": "string"},
    "catalog_gallery_file_ids": {
        "type": "array",
        "items": {"type": "string"},
        "description": "شناسه فایل‌های گالری کاتالوگ (حداکثر ۱۲)",
    },
    "suppliers": {
        "type": "array",
        "description": "تأمین‌کنندگان کالا. در ویرایش اگر ارسال شود جایگزین کامل است.",
        "items": _PRODUCT_SUPPLIER_ITEM_SCHEMA,
    },
    "opening_balance": _PRODUCT_OPENING_BALANCE_SCHEMA,
    "price_list_items": {
        "type": "array",
        "description": (
            "قیمت کالا در لیست‌های قیمت فرم تعریف کالا (عمده/همکار/ارز جدا). "
            "مثل UI بعد از ذخیره کالا upsert می‌شود؛ جایگزین همهٔ لیست‌ها نیست. "
            "شناسه لیست از list_price_lists، ارز از list_currencies."
        ),
        "items": _PRODUCT_PRICE_LIST_ITEM_SCHEMA,
    },
}

CREATE_PRODUCT_DESCRIPTION = (
    "ایجاد کالا یا خدمت با همان فیلدهای فرم تعریف کالا در رابط کاربری: "
    "واحد، قیمت فروش/خرید پایه، قیمت ارزی (sales_price_fx و price_fx_currency_id)، "
    "لیست‌های قیمت (price_list_items)، انبار، مالیات، بارکد، ویژگی، تأمین‌کننده، کاتالوگ، تعداد اولیه. "
    "name الزامی است. دسته از search_categories، انبار از list_warehouses، "
    "لیست قیمت از list_price_lists، ارز از list_currencies. "
    "فرمول ساخت (BOM) و نمونه‌های یونیک ابزار جدا دارند. نیاز به تأیید."
)

CREATE_PRODUCT_PARAMETERS_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "name": {"type": "string", "description": "نام کالا یا خدمت. همان نام کاربر را عیناً بفرست."},
        **_PRODUCT_WRITE_FIELDS_SCHEMA,
    },
    "required": ["name"],
}

UPDATE_PRODUCT_DESCRIPTION = (
    "ویرایش کالا/خدمت با همان فیلدهای فرم ویرایش در رابط کاربری، از جمله قیمت پایه/ارزی و price_list_items. "
    "فقط فیلدهای ارسالی تغییر می‌کنند. attribute_ids و suppliers در صورت ارسال جایگزین کامل‌اند. "
    "price_list_items مثل فرم upsert است نه حذف همهٔ قیمت‌های قبلی. نیاز به تأیید."
)

UPDATE_PRODUCT_PARAMETERS_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "product_id": {
            "type": "integer",
            "description": "شناسه کالا از search_products",
        },
        "name": {"type": "string", "description": "نام جدید"},
        **_PRODUCT_WRITE_FIELDS_SCHEMA,
    },
    "required": ["product_id"],
}


def normalize_product_item_type(raw: Any) -> Optional[str]:
    if raw is None:
        return None
    s = str(raw).strip()
    if not s:
        return None
    mapped = _PRODUCT_ITEM_TYPE_ALIASES.get(s) or _PRODUCT_ITEM_TYPE_ALIASES.get(s.lower())
    if mapped:
        return mapped
    raise ValueError("item_type باید کالا یا خدمت باشد (یا product/service).")


def normalize_product_inventory_mode(raw: Any) -> Optional[str]:
    if raw is None:
        return None
    s = str(raw).strip()
    if not s:
        return None
    mapped = _PRODUCT_INVENTORY_MODE_ALIASES.get(s) or _PRODUCT_INVENTORY_MODE_ALIASES.get(s.lower())
    if mapped:
        return mapped
    raise ValueError("inventory_mode باید bulk یا unique باشد.")


def _with_product_aliases(args: Dict[str, Any]) -> Dict[str, Any]:
    out = dict(args)
    for src, dest in _PRODUCT_FIELD_ALIASES.items():
        if dest not in out and src in out:
            out[dest] = out[src]
    if "category_id" not in out and "category" in out:
        raw = out.get("category")
        if isinstance(raw, int) or (isinstance(raw, str) and raw.strip().isdigit()):
            out["category_id"] = int(raw)
    if "general_barcodes" not in out and "barcodes" in out:
        raw = out.get("barcodes")
        if isinstance(raw, list):
            out["general_barcodes"] = ",".join(
                str(x).strip() for x in raw if str(x).strip()
            ) or None
        else:
            out["general_barcodes"] = _blank_to_none(raw)
    return out


def _int_id_list(raw: Any, field: str) -> Optional[List[int]]:
    if raw is None:
        return None
    if not isinstance(raw, list):
        raise ValueError(f"{field} باید آرایه عدد باشد.")
    out: List[int] = []
    for item in raw:
        if item is None or item == "":
            continue
        try:
            out.append(int(item))
        except (TypeError, ValueError) as exc:
            raise ValueError(f"{field} باید شامل شناسه عددی باشد.") from exc
    return out


def _str_id_list(raw: Any, field: str) -> Optional[List[str]]:
    if raw is None:
        return None
    if not isinstance(raw, list):
        raise ValueError(f"{field} باید آرایه رشته باشد.")
    return [s for s in (_blank_to_none(x) for x in raw) if s]


def _normalize_catalog_specifications(raw: Any) -> Optional[List[Dict[str, Any]]]:
    if raw is None:
        return None
    if not isinstance(raw, list):
        raise ValueError("catalog_specifications باید آرایه باشد.")
    out: List[Dict[str, Any]] = []
    for i, item in enumerate(raw):
        if not isinstance(item, dict):
            continue
        label = _blank_to_none(item.get("label") or item.get("title") or item.get("name"))
        if not label:
            continue
        row: Dict[str, Any] = {
            "label": label,
            "value": item.get("value") if item.get("value") is not None else "",
            "sort_order": int(item["sort_order"]) if item.get("sort_order") is not None else i,
        }
        if item.get("field_id") is not None:
            row["field_id"] = int(item["field_id"])
        out.append(row)
    return out


def _normalize_product_suppliers(raw: Any) -> Optional[List[Dict[str, Any]]]:
    if raw is None:
        return None
    if not isinstance(raw, list):
        raise ValueError("suppliers باید آرایه باشد.")
    out: List[Dict[str, Any]] = []
    for i, item in enumerate(raw):
        if not isinstance(item, dict):
            continue
        name = _blank_to_none(item.get("name"))
        person_id = item.get("person_id")
        if person_id is None and not name:
            continue
        row: Dict[str, Any] = {
            "name": name,
            "website": _blank_to_none(item.get("website")),
            "phone": _blank_to_none(item.get("phone")),
            "email": _blank_to_none(item.get("email")),
            "notes": _blank_to_none(item.get("notes")),
            "is_preferred": bool(item.get("is_preferred", False)),
            "sort_order": int(item["sort_order"]) if item.get("sort_order") is not None else i,
        }
        if person_id is not None and person_id != "":
            row["person_id"] = int(person_id)
        socials = _normalize_person_social_contacts(item.get("social_contacts"))
        if socials:
            row["social_contacts"] = socials
        out.append(row)
    return out


def _normalize_product_opening_balance(raw: Any) -> Optional[Dict[str, Any]]:
    if raw is None:
        return None
    if not isinstance(raw, dict):
        raise ValueError("opening_balance باید شیء باشد.")
    payload: Dict[str, Any] = {}
    qty = raw.get("quantity")
    if qty is None:
        qty = raw.get("qty") or raw.get("count")
    if qty is not None and qty != "":
        payload["quantity"] = float(qty)
    cost = raw.get("cost_price")
    if cost is None:
        cost = raw.get("cost") or raw.get("unit_cost")
    if cost is not None and cost != "":
        payload["cost_price"] = float(cost)
    if raw.get("warehouse_id") is not None and raw.get("warehouse_id") != "":
        payload["warehouse_id"] = int(raw["warehouse_id"])
    if raw.get("fiscal_year_id") is not None and raw.get("fiscal_year_id") != "":
        payload["fiscal_year_id"] = int(raw["fiscal_year_id"])
    if "clear" in raw:
        payload["clear"] = bool(raw["clear"])
    return payload or None


def _apply_product_write_fields(args: Dict[str, Any], payload: Dict[str, Any]) -> None:
    if "item_type" in args:
        payload["item_type"] = normalize_product_item_type(args.get("item_type"))
    if "code" in args:
        code = args.get("code")
        payload["code"] = None if code is None or code == "" else str(code).strip() or None
    _copy_optional_str(
        args,
        payload,
        "description",
        "main_unit",
        "secondary_unit",
        "base_sales_note",
        "base_purchase_note",
        "tax_code",
        "barcode",
        "general_barcodes",
        "image_file_id",
        "catalog_short_description",
        "catalog_expert_review",
        "catalog_brand",
        "catalog_model",
        "catalog_country_of_origin",
        "catalog_video_url",
    )
    for key in (
        "category_id",
        "price_fx_currency_id",
        "default_warehouse_id",
        "reorder_point",
        "min_order_qty",
        "lead_time_days",
        "tax_type_id",
        "tax_unit_id",
    ):
        _copy_optional_number(args, payload, key, as_int=True)
    for key in (
        "unit_conversion_factor",
        "base_sales_price",
        "base_purchase_price",
        "sales_price_fx",
        "purchase_price_fx",
        "sales_tax_rate",
        "purchase_tax_rate",
    ):
        _copy_optional_number(args, payload, key)
    for key in (
        "auto_update_base_from_fx",
        "track_inventory",
        "track_serial",
        "track_barcode",
        "is_sales_taxable",
        "is_purchase_taxable",
        "is_active",
        "is_public_catalog",
    ):
        _copy_optional_bool(args, payload, key)
    if "inventory_mode" in args:
        payload["inventory_mode"] = normalize_product_inventory_mode(args.get("inventory_mode"))
    if "attribute_ids" in args:
        payload["attribute_ids"] = _int_id_list(args.get("attribute_ids"), "attribute_ids") or []
    if "catalog_gallery_file_ids" in args:
        payload["catalog_gallery_file_ids"] = (
            _str_id_list(args.get("catalog_gallery_file_ids"), "catalog_gallery_file_ids") or []
        )
    if "catalog_specifications" in args:
        payload["catalog_specifications"] = (
            _normalize_catalog_specifications(args.get("catalog_specifications")) or []
        )
    if "suppliers" in args:
        payload["suppliers"] = _normalize_product_suppliers(args.get("suppliers")) or []
    if "opening_balance" in args:
        payload["opening_balance"] = _normalize_product_opening_balance(args.get("opening_balance"))


def build_create_product_payload(args: Dict[str, Any]) -> Dict[str, Any]:
    src = _with_product_aliases(args)
    name = _blank_to_none(src.get("name"))
    if not name:
        raise ValueError("name الزامی است.")
    payload: Dict[str, Any] = {"name": name}
    _apply_product_write_fields(src, payload)
    if payload.get("item_type") is None:
        payload["item_type"] = "کالا"
    return payload


def build_update_product_payload(args: Dict[str, Any]) -> Dict[str, Any]:
    src = _with_product_aliases(args)
    payload: Dict[str, Any] = {}
    if "name" in src:
        name = _blank_to_none(src.get("name"))
        if not name:
            raise ValueError("name نمی‌تواند خالی باشد.")
        payload["name"] = name
    _apply_product_write_fields(src, payload)
    return payload


def extract_product_price_list_items(args: Dict[str, Any]) -> Optional[List[Dict[str, Any]]]:
    """ردیف‌های لیست قیمت فرم کالا — در ProductCreateRequest نیستند و جدا upsert می‌شوند."""
    raw = args.get("price_list_items")
    if raw is None:
        return None
    if not isinstance(raw, list):
        raise ValueError("price_list_items باید آرایه باشد.")
    out: List[Dict[str, Any]] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        price = item.get("price")
        if price is None or price == "":
            continue
        row: Dict[str, Any] = {"price": float(price)}
        pl_id = item.get("price_list_id")
        if pl_id is None:
            pl_id = item.get("list_id")
        if pl_id is None:
            maybe_list = item.get("price_list")
            if isinstance(maybe_list, int) or (
                isinstance(maybe_list, str) and maybe_list.strip().isdigit()
            ):
                pl_id = maybe_list
        if pl_id is not None and pl_id != "":
            row["price_list_id"] = int(pl_id)
        name = _blank_to_none(item.get("price_list_name") or item.get("list_name"))
        if name is None and not isinstance(item.get("price_list"), (int, float)):
            name = _blank_to_none(item.get("price_list"))
        if name:
            row["price_list_name"] = name
        cur_id = item.get("currency_id")
        if cur_id is not None and cur_id != "":
            row["currency_id"] = int(cur_id)
        code = _blank_to_none(
            item.get("currency_code") or item.get("currency") or item.get("fx_code")
        )
        if code:
            row["currency_code"] = code
        if "price_list_id" not in row and "price_list_name" not in row:
            raise ValueError(
                "هر ردیف price_list_items باید price_list_id یا price_list_name داشته باشد. "
                "ابتدا list_price_lists را صدا بزن."
            )
        tier = _blank_to_none(item.get("tier_name") or item.get("tier"))
        if tier:
            row["tier_name"] = tier
        min_qty = item.get("min_qty")
        if min_qty is None:
            min_qty = item.get("min_quantity")
        if min_qty is not None and min_qty != "":
            row["min_qty"] = float(min_qty)
        out.append(row)
    return out
