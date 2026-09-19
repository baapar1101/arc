"""
مهارت‌های رسمی Hesabix ERP — seed برای مارکت‌پلیس.
"""
from __future__ import annotations

OFFICIAL_ERP_SKILLS = [
    {
        "skill_slug": "fiscal-year-close",
        "title": "بستن سال مالی",
        "description": (
            "راهنمای گام‌به‌گام بستن سال مالی در مارک‌استریت. "
            "وقتی کاربر از بستن سال، افتتاحیه، انتقال مانده یا پایان دوره مالی صحبت کرد استفاده کن."
        ),
        "skill_body": """# بستن سال مالی

## پیش‌نیاز
1. تمام اسناد دوره ثبت و قطعی شده باشند.
2. موجودی انبار و حساب‌ها تطبیق داده شده باشد.

## مراحل
1. `list_fiscal_years` — سال جاری و وضعیت را ببین.
2. `get_opening_balance` — مانده افتتاحیه را بررسی کن.
3. `get_sales_report` و `get_purchase_report` — عملکرد دوره.
4. `get_report(report_type=trial_balance)` — تراز آزمایشی.
5. اختلاف‌ها را گزارش بده؛ بدون تأیید صریح سند بستن ایجاد نکن.

## خروجی
- چک‌لیست موارد انجام‌شده
- هشدارهای باقی‌مانده
""",
        "allowed_tool_names": [
            "list_fiscal_years",
            "get_current_fiscal_year",
            "get_opening_balance",
            "get_sales_report",
            "get_purchase_report",
            "get_financial_summary",
            "get_report",
            "list_available_reports",
        ],
        "tags": ["مالی", "سال مالی", "مارک‌استریت"],
    },
    {
        "skill_slug": "sales-return",
        "title": "برگشت از فروش",
        "description": (
            "رویه ثبت برگشت کالا از فاکتور فروش. "
            "برای مرجوعی، برگشت، استرداد فاکتور فروش یا اصلاح فروش استفاده کن."
        ),
        "skill_body": """# برگشت از فروش

1. `get_invoice_details` — فاکتور مبدأ را بخوان.
2. `search_products` / `get_product_info` — اقلام را تأیید کن.
3. `search_warehouse_documents` — وضعیت انبار را بررسی کن.
4. خلاصه اقدام + درخواست تأیید قبل از ثبت سند برگشت.
""",
        "allowed_tool_names": [
            "search_invoices",
            "get_invoice_details",
            "search_products",
            "get_product_info",
            "search_warehouse_documents",
            "get_warehouse_stock_summary",
        ],
        "tags": ["فروش", "برگشت", "انبار"],
    },
    {
        "skill_slug": "inventory-reorder",
        "title": "سفارش مجدد موجودی",
        "description": (
            "تحلیل موجودی کم و پیشنهاد سفارش خرید. "
            "برای کمبود موجودی، نقطه سفارش، stockout استفاده کن."
        ),
        "skill_body": """# سفارش مجدد موجودی

1. `get_inventory_status` — اقلام کم‌موجود.
2. `get_warehouse_stock_summary` — موجودی به تفکیک انبار.
3. `search_products` — اطلاعات تأمین‌کننده در صورت نیاز.
4. جدول پیشنهادی: محصول | موجودی | پیشنهاد خرید
""",
        "allowed_tool_names": [
            "get_inventory_status",
            "get_warehouse_stock_summary",
            "search_products",
            "get_product_info",
            "search_persons",
        ],
        "tags": ["انبار", "خرید", "موجودی"],
    },
    {
        "skill_slug": "debtors-analysis",
        "title": "تحلیل بدهکاران",
        "description": (
            "تحلیل مطالبات و بدهکاران فروش. "
            "برای بدهی مشتریان، aging، مطالبات معوق استفاده کن."
        ),
        "skill_body": """# تحلیل بدهکاران

1. `get_debtors_report` — لیست بدهکاران.
2. `search_persons` / `get_person_balance` — جزئیات اشخاص مهم.
3. aging: ۰–۳۰، ۳۱–۶۰، ۶۱–۹۰، ۹۰+ روز بر اساس تاریخ فاکتور/مانده.
4. اولویت‌بندی بر اساس مبلغ و مدت بدهی.
5. پیشنهاد پیگیری برای ۵ بدهکار اول.
""",
        "allowed_tool_names": [
            "get_debtors_report",
            "search_persons",
            "get_person_balance",
            "search_invoices",
            "get_financial_summary",
        ],
        "tags": ["مالی", "مطالبات", "CRM"],
    },
    {
        "skill_slug": "monthly-financial-review",
        "title": "مرور مالی ماهانه",
        "description": (
            "گزارش مرور مالی ماهانه برای مدیر. "
            "برای خلاصه ماه، عملکرد مالی، سود و زیان ماهانه استفاده کن."
        ),
        "skill_body": """# مرور مالی ماهانه

1. `get_financial_summary` — تصویر کلی.
2. `get_sales_report` و `get_purchase_report` — دوره ماه جاری vs ماه قبل.
3. `get_report(report_type=pnl_period)` — سود و زیان دوره.
4. `get_cash_flow` — جریان نقد.
5. `get_debtors_report` — وضعیت مطالبات.

## شاخص‌ها (در صورت داده کافی)
- حاشیه سود ناخالص/خالص
- رشد فروش ماه به ماه

## خروجی
خلاصه اجرایی | فروش | خرید | سود/زیان | نقد | مطالبات | هشدارها
""",
        "allowed_tool_names": [
            "get_financial_summary",
            "get_sales_report",
            "get_purchase_report",
            "get_cash_flow",
            "get_business_dashboard",
            "get_report",
            "get_debtors_report",
            "list_available_reports",
        ],
        "tags": ["گزارش", "مدیریت", "مالی"],
    },
    {
        "skill_slug": "profit-loss-interpretation",
        "title": "تفسیر سود و زیان",
        "description": (
            "خواندن و تفسیر گزارش سود و زیان دوره‌ای یا تجمعی. "
            "برای سود، زیان، درآمد، هزینه، حاشیه سود استفاده کن."
        ),
        "skill_body": """# تفسیر سود و زیان

1. `get_report(report_type=pnl_period)` — سود و زیان دوره جاری.
2. در صورت نیاز `pnl_cumulative` — تجمعی.
3. `get_sales_report` — برای تفسیر درآمد عملیاتی.
4. اعداد را با واحد پول و بازه زمانی بیان کن.

## تفسیر برای مدیر
- درآمد vs هزینه اصلی
- حاشیه سود (در صورت داده)
- مقایسه با دوره قبل
- ۲–۳ نکته قابل اقدام
""",
        "allowed_tool_names": [
            "get_report",
            "list_available_reports",
            "get_financial_summary",
            "get_sales_report",
            "get_purchase_report",
        ],
        "tags": ["گزارش", "سود و زیان", "مالی"],
    },
    {
        "skill_slug": "accounting-document-guide",
        "title": "راهنمای سند حسابداری",
        "description": (
            "ثبت و تفسیر سند حسابداری، انتخاب حساب، تفاوت با فاکتور. "
            "برای سند حسابداری، دفتر، بدهکار بستانکار، تراز استفاده کن."
        ),
        "skill_body": """# راهنمای سند حسابداری

## تفکیک
- **فاکتور**: سند تجاری فروش/خرید
- **سند حسابداری**: ثبت دفتر (بدهکار/بستانکار)

## مراحل راهنمایی
1. `search_documents` — نمونه اسناد مشابه.
2. `get_document_details` — ساختار سند.
3. `get_report(trial_balance)` یا `accounts_review` — مانده حساب‌ها.
4. قبل از ثبت سند جدید: خلاصه سطرها + تأیید کاربر.

## نکات
- حساب درآمد/هزینه/دارایی/بدهی را درست انتخاب کن.
- سند باید متوازن باشد (جمع بدهکار = جمع بستانکار).
""",
        "allowed_tool_names": [
            "search_documents",
            "get_document_details",
            "get_report",
            "list_available_reports",
            "list_fiscal_years",
            "get_current_fiscal_year",
        ],
        "tags": ["حسابداری", "سند", "دفتر"],
    },
]
