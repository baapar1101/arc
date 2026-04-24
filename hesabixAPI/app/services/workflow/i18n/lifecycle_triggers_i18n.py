"""
ترجمه تریگرهای «چرخه حیات» (فاکتور، شخص) برای fa/en
"""
from __future__ import annotations

# فیلترهای فاکتور: مشترک ایجاد / ویرایش (همان config_schema)
_INVOICE_FA = {
    "field_enabled": "فعال",
    "field_enabled_desc": "غیرفعال کردن اجرای این تریگر",
    "field_invoice_type": "نوع فاکتور",
    "field_invoice_type_desc": "محدود به یکی از انواع فاکتور",
    "field_min_amount": "حداقل مبلغ",
    "field_min_amount_desc": "فقط اگر مبلغ از این مقدار بیشتر یا مساوی باشد",
    "field_max_amount": "حداکثر مبلغ",
    "field_max_amount_desc": "فقط اگر مبلغ از این مقدار کمتر یا مساوی باشد",
    "field_status_filter": "وضعیت فاکتور",
    "field_status_filter_desc": "فیلتر وضعیت (پیش‌نویس، تایید، ... در صورت وجود در داده)",
    "field_person_type_filter": "نوع طرف",
    "field_person_type_filter_desc": "مشتری / تامین‌کننده / ...",
    "field_currency_id": "ارز",
    "field_currency_id_desc": "فیلتر شناسه ارز سند",
    "field_include_tax_details": "جزئیات مالیات",
    "field_include_tax_details_desc": "افزودن جزئیات مالیات به trigger data در صورت پشتیبانی",
    "field_include_payment_status": "وضعیت پرداخت",
    "field_include_payment_status_desc": "افزودن وضعیت پرداخت در صورت پشتیبانی",
    "field_cooldown_seconds": "فاصلهٔ بین اجرا (ثانیه)",
    "field_cooldown_seconds_desc": "حداقل فاصله بین دو اجرای پشت‌سرهم",
    "field_timeout_seconds": "تایم‌اوت (ثانیه)",
    "field_timeout_seconds_desc": "راهنما برای اجرا؛ ممکن است توسط موتور متفاوت اعمال شود",
    "invoice_sales": "فروش",
    "invoice_purchase": "خرید",
    "invoice_return_sales": "برگشت فروش",
    "invoice_return_purchase": "برگشت خرید",
    "draft": "پیش‌نویس",
    "confirmed": "تایید شده",
    "cancelled": "لغو شده",
    "pending": "در انتظار",
    "customer": "مشتری",
    "supplier": "تامین‌کننده",
    "employee": "کارمند",
    "other": "سایر",
}

_INVOICE_EN = {
    "field_enabled": "Enabled",
    "field_enabled_desc": "Disable this trigger",
    "field_invoice_type": "Invoice type",
    "field_invoice_type_desc": "Restrict to a specific invoice type",
    "field_min_amount": "Minimum amount",
    "field_min_amount_desc": "Only when amount is greater or equal",
    "field_max_amount": "Maximum amount",
    "field_max_amount_desc": "Only when amount is less or equal",
    "field_status_filter": "Status filter",
    "field_status_filter_desc": "Filter by invoice status when present in data",
    "field_person_type_filter": "Counterparty type",
    "field_person_type_filter_desc": "Customer / supplier / etc.",
    "field_currency_id": "Currency",
    "field_currency_id_desc": "Filter by document currency ID",
    "field_include_tax_details": "Tax details",
    "field_include_tax_details_desc": "Append tax details to trigger data when supported",
    "field_include_payment_status": "Payment status",
    "field_include_payment_status_desc": "Append payment status when supported",
    "field_cooldown_seconds": "Cooldown (seconds)",
    "field_cooldown_seconds_desc": "Minimum delay between consecutive runs",
    "field_timeout_seconds": "Timeout (seconds)",
    "field_timeout_seconds_desc": "Execution hint; engine may differ",
    "invoice_sales": "Sales",
    "invoice_purchase": "Purchase",
    "invoice_return_sales": "Sales return",
    "invoice_return_purchase": "Purchase return",
    "draft": "Draft",
    "confirmed": "Confirmed",
    "cancelled": "Cancelled",
    "pending": "Pending",
    "customer": "Customer",
    "supplier": "Supplier",
    "employee": "Employee",
    "other": "Other",
}

INVOICE_WORKFLOW_TRIGGER_TRANSLATIONS = {
    "fa": {
        "trigger_name": "ایجاد فاکتور",
        "trigger_description": "هنگام ثبت / ایجاد فاکتور",
        **_INVOICE_FA,
    },
    "en": {
        "trigger_name": "Invoice created",
        "trigger_description": "When a new invoice is posted",
        **_INVOICE_EN,
    },
}

INVOICE_WORKFLOW_TRIGGER_UPDATED_TRANSLATIONS = {
    "fa": {
        "trigger_name": "ویرایش فاکتور",
        "trigger_description": "هنگام به‌روزرسانی فاکتور",
        **_INVOICE_FA,
    },
    "en": {
        "trigger_name": "Invoice updated",
        "trigger_description": "When an invoice is updated",
        **_INVOICE_EN,
    },
}

_PERSON_FA = {
    "field_person_type": "نوع شخص",
    "field_person_type_desc": "فیلتر روی نوع (مثلاً فقط مشتری)",
    "customer": "مشتری",
    "supplier": "تامین‌کننده",
    "employee": "کارمند",
    "other": "سایر",
}
_PERSON_EN = {
    "field_person_type": "Person type",
    "field_person_type_desc": "Filter by person type (e.g. customers only)",
    "customer": "Customer",
    "supplier": "Supplier",
    "employee": "Employee",
    "other": "Other",
}

PERSON_WORKFLOW_TRIGGER_TRANSLATIONS = {
    "fa": {
        "trigger_name": "ایجاد شخص",
        "trigger_description": "هنگام ایجاد طرف حساب / شخص جدید",
        **_PERSON_FA,
    },
    "en": {
        "trigger_name": "Contact created",
        "trigger_description": "When a new person/contact is created",
        **_PERSON_EN,
    },
}

PERSON_WORKFLOW_TRIGGER_UPDATED_TRANSLATIONS = {
    "fa": {
        "trigger_name": "ویرایش شخص",
        "trigger_description": "هنگام به‌روزرسانی اطلاعات شخص",
        **_PERSON_FA,
    },
    "en": {
        "trigger_name": "Contact updated",
        "trigger_description": "When a person/contact is updated",
        **_PERSON_EN,
    },
}
