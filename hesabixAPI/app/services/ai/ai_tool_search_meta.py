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
    "create_bank_account": {
        "aliases": ("حساب بانکی جدید", "ثبت حساب بانک"),
        "examples": ("یک حساب بانکی ملت ثبت کن",),
    },
    "delete_bank_account": {
        "aliases": ("حذف حساب بانکی",),
        "examples": ("این حساب بانکی را حذف کن",),
    },
    "create_cash_register": {
        "aliases": ("صندوق جدید", "ثبت صندوق"),
        "examples": ("یک صندوق فروشگاهی بساز",),
    },
    "create_petty_cash": {
        "aliases": ("تنخواه جدید", "ثبت تنخواه"),
        "examples": ("یک تنخواه گردان ثبت کن",),
    },
    "upsert_opening_balance": {
        "aliases": ("ذخیره تراز افتتاحیه", "ثبت افتتاحیه"),
        "examples": ("تراز افتتاحیه را ذخیره کن",),
    },
    "post_opening_balance": {
        "aliases": ("نهایی‌سازی تراز افتتاحیه",),
        "examples": ("تراز افتتاحیه را نهایی کن",),
    },
    "create_fixed_asset": {
        "aliases": ("ثبت دارایی ثابت", "اموال جدید"),
        "examples": ("یک دارایی ثابت ثبت کن",),
    },
    "capitalize_fixed_asset": {
        "aliases": ("سرمایه‌گذاری دارایی",),
        "examples": ("این دارایی را سرمایه‌گذاری کن",),
    },
    "click_to_call": {
        "aliases": ("تماس خروجی", "کلیک تو کال"),
        "examples": ("با این شماره تماس بگیر",),
    },
    "create_barcode_label_from_preset": {
        "aliases": ("طرح برچسب از preset", "برچسب بارکد جدید"),
        "examples": ("یک طرح برچسب از preset بساز",),
    },
    "update_business_info": {
        "aliases": ("ویرایش مشخصات کسب‌وکار", "تغییر نام کسب‌وکار"),
        "examples": ("مشخصات کسب‌وکار را ویرایش کن",),
    },
    "update_document_numbering_settings": {
        "aliases": ("شماره‌گذاری اسناد", "پیشوند شماره سند"),
        "examples": ("شماره‌گذاری اسناد را ویرایش کن",),
    },
    "create_project": {
        "aliases": ("ثبت پروژه", "پروژه جدید"),
        "examples": ("یک پروژه ساختمانی ثبت کن",),
    },
    "create_person_group": {
        "aliases": ("گروه اشخاص جدید", "گروه مشتریان"),
        "examples": ("یک گروه اشخاص جدید بساز",),
    },
    "update_person_credit": {
        "aliases": ("سقف اعتبار مشتری", "اعتبار این شخص"),
        "examples": ("سقف اعتبار این مشتری را عوض کن",),
    },
    "create_credit_installment_plan": {
        "aliases": ("طرح اقساط جدید", "پلن اقساط"),
        "examples": ("یک طرح اقساط جدید بساز",),
    },
    "create_product_bundle": {
        "aliases": ("باندل جدید", "بسته کالا", "باندل کالا"),
        "examples": ("یک باندل کالا بساز",),
    },
    "search_product_bundles": {
        "aliases": ("باندل‌ها", "بسته‌های کالا"),
        "examples": ("باندل‌های کالا را لیست کن",),
    },
    "create_price_list": {
        "aliases": ("لیست قیمت جدید", "قیمت عمده جدید"),
        "examples": ("یک لیست قیمت عمده بساز",),
    },
    "upsert_price_list_item": {
        "aliases": ("قیمت کالا در لیست", "قیمت عمده این کالا"),
        "examples": ("قیمت این کالا را در لیست عمده ثبت کن",),
    },
    "create_product_category": {
        "aliases": ("دسته کالا جدید", "دسته‌بندی جدید"),
        "examples": ("یک دسته کالا جدید بساز",),
    },
    "create_product_instance": {
        "aliases": ("کالای یونیک", "سریال کالا"),
        "examples": ("یک کالای یونیک با سریال ثبت کن",),
    },
    "create_warehouse": {
        "aliases": ("انبار جدید",),
        "examples": ("یک انبار جدید بساز",),
    },
    "create_warehouse_location": {
        "aliases": ("محل انبار", "قفسه انبار"),
        "examples": ("یک قفسه در این انبار بساز",),
    },
    "create_frequent_description": {
        "aliases": ("شرح پرتکرار",),
        "examples": ("یک شرح پرتکرار اضافه کن",),
    },
    "create_catalog_spec_field": {
        "aliases": ("فیلد مشخصات", "مشخصات کاتالوگ"),
        "examples": ("یک فیلد مشخصات کاتالوگ بساز",),
    },
    "create_currency_rate": {
        "aliases": ("نرخ تسعیر", "نرخ ارز"),
        "examples": ("نرخ تسعیر دلار را ثبت کن",),
    },
    "create_loan_facility": {
        "aliases": ("تسهیل دریافتی", "وام دریافتی"),
        "examples": ("یک تسهیل دریافتی ثبت کن",),
    },
    "create_fiscal_year": {
        "aliases": ("سال مالی جدید",),
        "examples": ("یک سال مالی جدید بساز",),
    },
    "close_fiscal_year": {
        "aliases": ("بستن سال مالی", "اختتامیه"),
        "examples": ("سال مالی را ببند",),
    },
    "enqueue_quick_sale": {
        "aliases": ("فروش سریع", "فاکتور فروش سریع"),
        "examples": ("یک فروش سریع ثبت کن",),
    },
    "save_customer_club_reward": {
        "aliases": ("جایزه باشگاه",),
        "examples": ("یک جایزه باشگاه مشتریان بساز",),
    },
    "create_business_notification_template": {
        "aliases": ("قالب اعلان", "قالب پیامک"),
        "examples": ("یک قالب اعلان بساز",),
    },
    "create_goods_expense_income": {
        "aliases": ("کالای هزینه‌شده", "کالای درآمدشده"),
        "examples": ("یک سند کالای هزینه‌شده ثبت کن",),
    },
    "get_product_category_tree": {
        "aliases": ("درخت دسته‌بندی", "درخت دسته کالا"),
        "examples": ("درخت دسته‌بندی کالا را نشان بده",),
    },
    "list_project_documents": {
        "aliases": ("اسناد پروژه", "اسناد همین پروژه"),
        "examples": ("اسناد همین پروژه را نشان بده",),
    },
    "delete_project": {
        "aliases": ("حذف پروژه",),
        "examples": ("این پروژه را حذف کن",),
    },
    "get_person_group": {
        "aliases": ("جزئیات گروه اشخاص",),
        "examples": ("جزئیات این گروه اشخاص را بده",),
    },
    "update_credit_settings": {
        "aliases": ("تنظیمات اعتبار", "سقف اعتبار پیش‌فرض"),
        "examples": ("تنظیمات اعتبار کسب‌وکار را عوض کن",),
    },
    "list_fiscal_years": {
        "aliases": ("سال‌های مالی", "لیست سال مالی"),
    },
    "get_check_details": {
        "aliases": ("جزئیات چک", "جزئیات همان چک"),
    },
    "get_report": {
        "aliases": ("گزارش یکپارچه", "گزارش", "دفتر کل", "تراز آزمایشی", "سود و زیان", "ترازنامه", "سن بدهی", "اقساط", "تسعیر"),
        "examples": ("تراز آزمایشی فروردین", "گزارش سود و زیان", "سن بدهی مشتریان", "صورت جریان وجوه نقد"),
    },
    "list_mcp_categories": {
        "aliases": ("دسته ابزار", "چه ابزارهایی داری", "فهرست ابزار"),
        "examples": ("چه دسته‌هایی از ابزار در این اتصال هست؟",),
    },
    "search_mcp_tools": {
        "aliases": ("جستجوی ابزار", "ابزار MCP", "چه ابزاری"),
        "examples": ("ابزار تراز آزمایشی چیست؟", "ابزار ثبت فاکتور را پیدا کن"),
    },
    "search_documents": {
        "aliases": ("اسناد حسابداری", "سند حسابداری"),
    },
    "get_document_details": {
        "aliases": ("جزئیات سند", "سند را باز کن"),
    },
    "get_document_types_summary": {
        "aliases": ("خلاصه انواع سند", "آمار نوع سند"),
        "examples": ("هر نوع سند چندتا داریم؟",),
    },
    "create_manual_document": {
        "aliases": ("سند دستی", "ثبت سند حسابداری", "سند حسابداری جدید", "journal entry"),
        "examples": (
            "یک سند حسابداری دستی ثبت کن",
            "سند دستی متوازن بزن",
        ),
    },
    "update_manual_document": {
        "aliases": ("ویرایش سند دستی", "اصلاح سند حسابداری"),
        "examples": ("سطرهای سند دستی را ویرایش کن",),
    },
    "delete_manual_document": {
        "aliases": ("حذف سند دستی", "حذف سند حسابداری"),
        "examples": ("این سند دستی را حذف کن",),
    },
    "bulk_delete_manual_documents": {
        "aliases": ("حذف گروهی سند دستی", "حذف چند سند حسابداری"),
        "examples": ("این چند سند دستی را حذف کن",),
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
