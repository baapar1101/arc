"""
مهارت‌های رسمی Hesabix ERP — seed برای مارکت‌پلیس.
"""
from __future__ import annotations

OFFICIAL_ERP_SKILLS = [
    {
        "skill_slug": "fiscal-year-close",
        "title": "بستن سال مالی",
        "description": (
            "راهنمای گام‌به‌گام بستن سال مالی در حسابیکس. "
            "وقتی کاربر از بستن سال، افتتاحیه، انتقال مانده یا پایان دوره مالی صحبت کرد استفاده کن."
        ),
        "skill_body": """# بستن سال مالی

## پیش‌نیاز
1. تمام اسناد دوره ثبت و قطعی شده باشند.
2. موجودی انبار و حساب‌ها تطبیق داده شده باشد.

## مراحل
1. `list_fiscal_years` — سال جاری و وضعیت را ببین.
2. `get_opening_balance` — مانده افتتاحیه را بررسی کن.
3. گزارش‌های `get_sales_report` و `get_purchase_report` را برای دوره بگیر.
4. اختلاف‌ها را به کاربر گزارش بده؛ بدون تأیید صریح سند بستن ایجاد نکن.

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
        ],
        "tags": ["مالی", "سال مالی", "حسابیکس"],
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
3. اولویت‌بندی بر اساس مبلغ و مدت بدهی.
4. پیشنهاد پیگیری برای ۵ بدهکار اول.
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
2. `get_sales_report` و `get_purchase_report` — دوره ماه جاری.
3. `get_cash_flow` — جریان نقد.
4. ساختار خروجی: خلاصه | فروش | خرید | نقد | هشدارها
""",
        "allowed_tool_names": [
            "get_financial_summary",
            "get_sales_report",
            "get_purchase_report",
            "get_cash_flow",
            "get_business_dashboard",
        ],
        "tags": ["گزارش", "مدیریت", "مالی"],
    },
]
