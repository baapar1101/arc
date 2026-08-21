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
        "aliases": ("گزارش فروش", "میزان فروش", "فروش این ماه", "how much did we sell"),
        "keywords": ("فروش ماهانه", "sales report", "did we sell"),
        "examples": (
            "فروش این ماه را گزارش کن",
            "گزارش فروش بده",
            "how much did we sell last week",
        ),
    },
    "get_purchase_report": {
        "aliases": ("گزارش خرید", "خرید این ماه"),
        "examples": ("گزارش خرید ماه گذشته",),
    },
    "get_debtors_report": {
        "aliases": ("گزارش بدهکاران", "بدهکاران", "who owes us", "owes us money"),
        "examples": ("گزارش بدهکاران", "what do they owe"),
    },
    "get_creditors_report": {
        "aliases": ("گزارش بستانکاران", "بستانکاران", "طلبکارند", "طلبکار"),
        "examples": ("لیست بستانکاران", "چه کسانی از ما طلبکارند"),
    },
    "search_persons": {
        "aliases": ("مشتری", "اشخاص", "طرف حساب", "طرف‌حساب", "طرف‌حساب‌ها"),
        "examples": ("مشتری علی را پیدا کن", "لیست مشتریان", "طرف‌حساب‌ها را نشان بده"),
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
        "aliases": ("موجودی", "موجودی انبار", "کم‌موجود", "کالاهای کم‌موجود"),
        "examples": ("موجودی انبار چقدر است", "کالاهای کم‌موجود را نشان بده"),
    },
    "get_product_kardex": {
        "aliases": ("کاردکس", "کاردکس کالا"),
        "examples": ("کاردکس کالای پیچ",),
    },
    "query_business_data": {
        "aliases": ("پرس‌وجو", "query"),
        "examples": ("موجودی و فاکتور را با فیلتر پیشرفته بده",),
    },
    "export_business_data": {
        "aliases": ("خروجی اکسل", "export", "دانلود لیست"),
        "examples": ("خروجی اکسل فاکتورهای این ماه",),
    },
    "list_workflows": {
        "aliases": ("لیست اتوماسیون", "گردش‌کارها", "گردش کارها", "اتوماسیونا"),
        "examples": ("لیست گردش‌کارهای اتوماسیون",),
    },
    "execute_workflow": {
        "aliases": ("اجرای اتوماسیون", "اجرای workflow", "گردش‌کار را اجرا", "run this workflow"),
        "examples": ("این گردش‌کار را اجرا کن", "run this workflow now"),
    },
    "get_workflow": {
        "aliases": ("جزئیات گردش‌کار", "جزئیات اتوماسیون"),
        "examples": ("گردش‌کار ۱۲ را باز کن",),
    },
    "update_workflow": {
        "aliases": ("ویرایش اتوماسیون", "به‌روز کردن گردش‌کار"),
        "examples": ("این گردش‌کار را به‌روز کن",),
    },
    "delete_workflow": {
        "aliases": ("حذف اتوماسیون", "حذف گردش‌کار"),
        "examples": ("این اتوماسیون را حذف کن",),
    },
    "poll_workflow_execution": {
        "aliases": ("نتیجه اجرا", "وضعیت اجرای گردش‌کار", "poll workflow"),
        "examples": ("نتیجه اجرای workflow را بگیر",),
    },
    "get_workflow_execution_debug": {
        "aliases": ("دیباگ اجرا", "دیباگ اتوماسیون", "debug workflow"),
        "examples": ("دیباگ اجرای اتوماسیون",),
    },
    "list_workflow_executions": {
        "aliases": ("اجراهای workflow", "تاریخچه اجرای اتوماسیون"),
        "examples": ("اجراهای workflow را نشان بده",),
    },
    "list_workflow_builtin_nodes": {
        "aliases": ("نودهای آماده", "نود آماده گردش‌کار"),
        "examples": ("نودهای آماده گردش‌کار",),
    },
    "list_workflow_action_catalog": {
        "aliases": ("کاتالوگ اکشن", "اکشن گردش‌کار"),
        "examples": ("کاتالوگ اکشن‌های گردش‌کار",),
    },
    "list_workflow_trigger_catalog": {
        "aliases": ("تریگر گردش‌کار", "کاتالوگ تریگر", "تریگرهای اتوماسیون"),
        "examples": ("تریگرهای اتوماسیون را لیست کن",),
    },
    "get_workflow_component_schema": {
        "aliases": ("اسکیمای کامپوننت", "schema کامپوننت workflow"),
        "examples": ("اسکیمای کامپوننت workflow",),
    },
    "get_workflow_design_rules": {
        "aliases": ("قوانین طراحی اتوماسیون", "قوانین گردش‌کار"),
        "examples": ("قوانین طراحی اتوماسیون چیست",),
    },
    "validate_workflow_draft": {
        "aliases": ("اعتبارسنجی پیش‌نویس", "اعتبارسنجی گردش‌کار", "validate workflow"),
        "examples": ("پیش‌نویس گردش‌کار را اعتبارسنجی کن",),
    },
    "test_workflow": {
        "aliases": ("تست اتوماسیون", "تست گردش‌کار", "test workflow", "test this automation"),
        "examples": ("اتوماسیون را تست کن", "test this automation"),
    },
    "list_frequent_descriptions": {
        "aliases": ("شرح پرتکرار", "شرح‌های پرتکرار", "شرح اسناد"),
    },
    "get_document_numbering_settings": {
        "aliases": ("شماره‌گذاری اسناد", "شماره گذاری سند"),
    },
    "list_warehouse_placements": {
        "aliases": ("جانمایی انبار", "جانمایی کالا"),
    },
    "list_warehouse_locations": {
        "aliases": ("محل‌های انبار", "محل انبار"),
    },
    "list_cash_registers": {
        "aliases": ("صندوق", "صندوق‌ها", "صندوق فروشگاهی"),
    },
    "list_petty_cash": {
        "aliases": ("تنخواه", "تنخواه گردان"),
    },
    "get_opening_balance": {
        "aliases": ("مانده افتتاحیه", "افتتاحیه حساب"),
    },
    "list_fiscal_years": {
        "aliases": ("سال‌های مالی", "لیست سال مالی"),
    },
    "get_check_details": {
        "aliases": ("جزئیات چک", "جزئیات همان چک"),
    },
    "get_report": {
        "aliases": ("گزارش یکپارچه", "گزارش", "دفتر کل", "تراز آزمایشی", "سود و زیان", "ترازنامه"),
        "examples": ("تراز آزمایشی فروردین", "گزارش سود و زیان"),
    },
    "search_documents": {
        "aliases": ("اسناد حسابداری", "سند حسابداری"),
    },
    "get_document_details": {
        "aliases": ("جزئیات سند", "سند را باز کن"),
    },
    "list_boms": {
        "aliases": ("لیست BOM", "صورت مواد"),
    },
    "get_bom_details": {
        "aliases": ("جزئیات BOM", "جزئیات صورت مواد"),
    },
    "search_repair_orders": {
        "aliases": ("سفارش تعمیر", "تعمیر"),
    },
    "get_repair_order_details": {
        "aliases": ("جزئیات تعمیر", "جزئیات سفارش تعمیر"),
    },
    "search_projects": {
        "aliases": ("پروژه‌ها", "لیست پروژه"),
    },
    "get_project_summary": {
        "aliases": ("خلاصه پروژه",),
    },
    "list_distribution_routes": {
        "aliases": ("مسیر توزیع", "مسیرهای توزیع"),
    },
    "search_warranty_codes": {
        "aliases": ("کد گارانتی", "گارانتی"),
    },
    "list_queryable_fields": {
        "aliases": ("فیلدهای قابل پرس‌وجو", "queryable fields"),
    },
    "batch_query_business_data": {
        "aliases": ("پرس‌وجوی چند موجودیت", "batch query"),
    },
    "get_quick_sales_settings": {
        "aliases": ("فروش سریع", "تنظیمات فروش سریع"),
    },
    "list_business_notification_logs": {
        "aliases": ("لاگ اعلان", "اعلان‌های ارسال‌شده"),
    },
    "list_business_notification_templates": {
        "aliases": ("قالب اعلان", "قالب پیامک"),
    },
    "hscript_fix_script": {
        "aliases": ("اصلاح اسکریپت", "fix hscript"),
    },
    "hscript_validate_script": {
        "aliases": ("اعتبارسنجی اسکریپت", "validate hscript"),
    },
    "hscript_run_preview": {
        "aliases": ("پیش‌نمایش hscript", "preview اسکریپت"),
    },
    "list_product_attributes": {
        "aliases": ("ویژگی کالا", "ویژگی‌های کالا"),
    },
    "get_product_attribute": {
        "aliases": ("جزئیات ویژگی کالا",),
    },
    "list_price_list_items": {
        "aliases": ("اقلام لیست قیمت",),
    },
    "get_loan_facility": {
        "aliases": ("جزئیات وام", "تسهیلات وام"),
    },
    "list_loan_facilities": {
        "aliases": ("لیست تسهیلات", "تسهیلات"),
    },
    "list_credit_installment_plans": {
        "aliases": ("اقساط اعتبار",),
    },
    "get_business_credit_settings": {
        "aliases": ("تنظیمات اعتبار", "اعتبار کسب‌وکار"),
    },
    "get_person_credit": {
        "aliases": ("اعتبار مشتری",),
    },
    "search_production_documents": {
        "aliases": ("اسناد تولید",),
    },
    "search_product_instances": {
        "aliases": ("سریال کالا", "سریال کالاها"),
    },
    "update_product_attribute": {
        "aliases": ("ویرایش ویژگی کالا",),
    },
    "delete_product_attribute": {
        "aliases": ("حذف ویژگی کالا",),
    },
    "set_default_report_template": {
        "aliases": ("قالب پیش‌فرض گزارش",),
    },
    "publish_report_template": {
        "aliases": ("انتشار قالب گزارش",),
    },
    "get_report_template_scope_catalog": {
        "aliases": ("کاتالوگ محدوده قالب",),
    },
    "adjust_customer_club_points": {
        "aliases": ("امتیاز باشگاه را", "کم و زیاد کردن امتیاز"),
    },
    "recalculate_customer_club_rfm": {
        "aliases": ("محاسبه مجدد RFM", "RFM را دوباره"),
    },
    "search_customer_club_rfm_persons": {
        "aliases": ("مشتریان RFM",),
    },
    "list_customer_club_tiers": {
        "aliases": ("سطح‌های باشگاه", "سطح باشگاه"),
    },
    "invoke_business_connector": {
        "aliases": ("کانکتور", "وب‌سرویس خارجی", "connector call"),
        "examples": ("کانکتور قیمت را صدا بزن",),
    },
    "create_workflow": {
        "aliases": ("اتوماسیون جدید", "گردش کار جدید", "workflow جدید"),
        "examples": ("اتوماسیون جدید بساز",),
    },
    "read_memory": {
        "aliases": ("حافظه دستیار", "چی درباره من می‌دانی"),
        "examples": ("چی درباره من می‌دانی؟",),
    },
    "upsert_memory_entry": {
        "aliases": ("به خاطر بسپار", "ذخیره در حافظه", "remember this", "remember I prefer", "یادت باشه"),
        "examples": ("یادت باشه گزارش‌ها را به تومان بدهی", "remember this: invoices in toman"),
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
    "list_bank_accounts": {
        "aliases": ("حساب‌های بانکی", "لیست حساب بانکی", "حساب بانکی"),
    },
    "search_expense_income": {
        "aliases": ("هزینه‌های این ماه", "لیست هزینه", "هزینه"),
    },
    "search_checks": {
        "aliases": ("چک‌های در جریان", "لیست چک", "چک"),
    },
    "search_transfers": {
        "aliases": ("انتقال‌های بانکی", "لیست انتقال", "انتقال‌های این هفته"),
    },
    "get_wallet_metrics": {
        "aliases": ("متریک کیف پول", "متریک wallet"),
    },
    "get_lead_funnel_report": {
        "aliases": ("قیف فروش", "قیف سرنخ", "قیف فروش سرنخ"),
    },
    "get_pipeline_report": {
        "aliases": ("پایپلاین", "پایپ‌لاین", "گزارش پایپلاین", "گزارش پایپ‌لاین"),
    },
    "get_tax_data_quality": {
        "aliases": ("کیفیت داده مالیاتی", "کیفیت داده مالیات"),
    },
    "update_account": {
        "aliases": ("ویرایش سرفصل", "سرفصل حساب را ویرایش"),
    },
    "delete_receipt_payment": {
        "aliases": ("این دریافت را حذف", "حذف دریافت"),
    },
    "get_report_template": {
        "aliases": ("جزئیات قالب چاپ", "جزئیات قالب گزارش"),
    },
    "resolve_currency_rate": {
        "aliases": ("نرخ دلار", "نرخ ارز را بگیر"),
    },
    "list_currency_rates": {
        "aliases": ("نرخ‌های ارز", "لیست نرخ ارز"),
    },
    "search_deals": {
        "aliases": ("معاملات باز", "لیست معامله", "معامله‌ها"),
    },
    "list_user_notifications": {
        "aliases": ("اعلان‌های من", "اعلانات من"),
    },
    "list_business_users": {
        "aliases": ("کاربران این کسب‌وکار", "کاربران کسب‌وکار"),
    },
    "update_check": {
        "aliases": ("ویرایش چک", "چک را ویرایش", "ویرایش چک برگشتی"),
    },
    "update_transfer": {
        "aliases": ("ویرایش انتقال", "ویرایش انتقال بین حساب"),
    },
    "list_announcements": {
        "aliases": ("اعلانات سامانه", "اعلانات"),
    },
    "list_my_businesses": {
        "aliases": ("کسب‌وکارهای من", "لیست کسب‌وکارهای من"),
    },
    "get_business_dashboard": {
        "aliases": ("داشبورد", "داشبورد کسب‌وکار"),
        "keywords": ("گزارش کلی", "اوضاع", "خلاصه وضعیت", "نمای کلی"),
        "examples": (
            "یک گزارش کلی از اوضاع بده",
            "داشبورد کسب‌وکار را نشان بده",
        ),
    },
    "get_business_info": {
        "aliases": ("اطلاعات کسب‌وکار", "مشخصات کسب‌وکار"),
        "keywords": ("اطلاعات",),
        "examples": ("اطلاعات این کسب‌وکار",),
    },
    "get_person_balance": {
        "keywords": ("مانده",),
        "examples": ("مانده حساب علی چقدر است",),
    },
}


def search_meta_for(name: str) -> SearchMeta:
    return dict(TOOL_SEARCH_META.get(name) or {})
