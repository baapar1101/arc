"""Search metadata enrichment for important tools.

Alias/example فقط وقتی کاربر واقعاً این عبارات را می‌گوید.
ابزارهای دم‌بلند بدون enrichment می‌مانند (aliases اختیاری است).
"""
from __future__ import annotations

from typing import Dict, Tuple, TypedDict


class SearchMeta(TypedDict, total=False):
    aliases: Tuple[str, ...]
    keywords: Tuple[str, ...]
    examples: Tuple[str, ...]


TOOL_SEARCH_META: Dict[str, SearchMeta] = {
    "search_invoices": {
        "aliases": ("فاکتور", "فاکتور فروش", "صورتحساب", "لیست فاکتور"),
        "keywords": ("invoice", "sales invoice", "فاکتورهای"),
        "examples": (
            "فاکتورهای فروش این ماه را نشان بده",
            "فاکتور علی را پیدا کن",
        ),
    },
    "get_invoice_details": {
        "aliases": ("جزئیات فاکتور", "اقلام فاکتور"),
        "examples": (
            "فاکتور شماره ۱۲۳ را کامل نشان بده",
            "اقلام و مالیات این فاکتور چیست؟",
        ),
    },
    "create_invoice": {
        "aliases": ("فاکتور جدید", "ثبت فاکتور", "بزن فاکتور"),
        "examples": (
            "یه فاکتور فروش برای علی بزن",
            "فاکتور جدید ایجاد کن",
        ),
    },
    "delete_invoice": {
        "aliases": ("حذف فاکتور", "فاکتور را پاک کن"),
        "examples": ("این فاکتور را حذف کن",),
    },
    "update_invoice": {
        "aliases": ("ویرایش فاکتور", "اصلاح فاکتور"),
        "examples": ("مبلغ فاکتور را ویرایش کن",),
    },
    "get_sales_report": {
        "aliases": ("گزارش فروش", "میزان فروش", "فروش این ماه"),
        "keywords": ("فروش ماهانه", "sales report"),
        "examples": (
            "فروش این ماه را گزارش کن",
            "گزارش فروش بده",
        ),
    },
    "get_purchase_report": {
        "aliases": ("گزارش خرید", "خرید این ماه"),
        "examples": ("گزارش خرید ماه گذشته",),
    },
    "get_debtors_report": {
        "aliases": ("گزارش بدهکاران", "بدهکاران"),
        "examples": ("گزارش بدهکاران",),
    },
    "get_creditors_report": {
        "aliases": ("گزارش بستانکاران", "بستانکاران"),
        "examples": ("لیست بستانکاران",),
    },
    "search_persons": {
        "aliases": ("مشتری", "اشخاص", "طرف حساب"),
        "examples": ("مشتری علی را پیدا کن", "لیست مشتریان"),
    },
    "create_person": {
        "aliases": ("مشتری جدید", "شخص جدید"),
        "examples": ("یک مشتری به نام علی اضافه کن",),
    },
    "delete_person": {
        "aliases": ("حذف مشتری", "حذف شخص"),
        "examples": ("این شخص را حذف کن",),
    },
    "search_products": {
        "aliases": ("کالا", "محصول", "لیست کالا"),
        "examples": ("لیست محصولات و کالاها",),
    },
    "create_product": {
        "aliases": ("کالای جدید", "محصول جدید"),
        "examples": ("یک کالای جدید با بارکد اضافه کن",),
    },
    "get_inventory_status": {
        "aliases": ("موجودی", "موجودی انبار"),
        "examples": ("موجودی انبار چقدر است",),
    },
    "get_product_kardex": {
        "aliases": ("کاردکس", "کاردکس کالا"),
        "examples": ("کاردکس کالای پیچ",),
    },
    "query_business_data": {
        "aliases": ("پرس‌وجو", "query"),
        "examples": ("موجودی و فاکتور را با فیلتر پیشرفته بده",),
    },
    "get_report": {
        "aliases": ("گزارش یکپارچه", "گزارش"),
        "examples": ("تراز آزمایشی فروردین", "گزارش سود و زیان"),
    },
    "export_business_data": {
        "aliases": ("خروجی اکسل", "export", "دانلود لیست"),
        "examples": ("خروجی اکسل فاکتورهای این ماه",),
    },
    "execute_workflow": {
        "aliases": ("اجرای اتوماسیون", "اجرای workflow"),
        "examples": ("این گردش‌کار را اجرا کن",),
    },
    "list_workflows": {
        "aliases": ("لیست اتوماسیون", "گردش‌کارها"),
        "examples": ("لیست گردش‌کارهای اتوماسیون",),
    },
    "create_workflow": {
        "aliases": ("اتوماسیون", "گردش کار جدید", "workflow جدید"),
        "examples": ("اتوماسیون جدید بساز",),
    },
    "read_memory": {
        "aliases": ("حافظه دستیار", "چی درباره من می‌دانی"),
        "examples": ("چی درباره من می‌دانی؟",),
    },
    "upsert_memory_entry": {
        "aliases": ("به خاطر بسپار", "ذخیره در حافظه"),
        "examples": ("یادت باشه گزارش‌ها را به تومان بدهی",),
    },
    "delete_memory_entry": {
        "aliases": ("فراموش کن", "حذف از حافظه"),
        "examples": ("این مورد را از حافظه حذف کن",),
    },
    "get_wallet_overview": {
        "aliases": ("کیف پول", "موجودی کیف پول"),
        "examples": ("موجودی کیف پول کسب‌وکار",),
    },
    "list_accounts": {
        "aliases": ("سرفصل", "حساب کل", "coding"),
        "examples": ("سرفصل حساب‌های کل",),
    },
    "search_leads": {
        "aliases": ("سرنخ", "لیست سرنخ"),
        "examples": ("سرنخ‌های این هفته را لیست کن",),
    },
    "get_basalam_overview": {
        "aliases": ("باسلام", "basalam", "خلاصه باسلام"),
        "examples": ("وضعیت سینک باسلام چطور است",),
    },
    "invoke_business_connector": {
        "aliases": ("کانکتور", "وب‌سرویس خارجی"),
        "examples": ("کانکتور قیمت را صدا بزن",),
    },
}


def search_meta_for(name: str) -> SearchMeta:
    return dict(TOOL_SEARCH_META.get(name) or {})
