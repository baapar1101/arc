# noqa: D100
"""انواع رویداد قالب نوتیفیکیشن کسب‌وکار — یک منبع برای مهاجرت و اسکریپت seed."""

from __future__ import annotations

# متغیرهای مشترک فاکتور (ارسال دستی + دادهٔ ورک‌فلو / غنی‌سازی سند)
INVOICE_TEMPLATE_VARIABLES: list[dict[str, str]] = [
    {"key": "invoice_number", "type": "string", "description": "شماره فاکتور"},
    {"key": "invoice_code", "type": "string", "description": "کد سند فاکتور"},
    {"key": "customer_name", "type": "string", "description": "نام طرف حساب در سند"},
    {"key": "invoice_date", "type": "date", "description": "تاریخ فاکتور"},
    {"key": "amount", "type": "number", "description": "مبلغ کل (سناریوهای دستی یا معادل با total_amount)"},
    {"key": "total_amount", "type": "number", "description": "مبلغ کل از تریگر ورک‌فلو (invoice.created)"},
    {"key": "final_amount", "type": "number", "description": "مبلغ نهایی بعد از تخفیف و مالیات"},
    {"key": "tax_amount", "type": "number", "description": "جمع مالیات"},
    {"key": "discount_amount", "type": "number", "description": "جمع تخفیف"},
    {"key": "due_date", "type": "date", "description": "تاریخ سررسید"},
    {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
    {"key": "business_phone", "type": "string", "description": "تلفن کسب‌وکار"},
]

INVOICE_SHARE_LINK_TEMPLATE_VARIABLES: list[dict[str, str]] = [
    {"key": "share_link", "type": "string", "description": "لینک کوتاه مشاهده و پرداخت فاکتور"},
    {"key": "customer_mobile", "type": "string", "description": "شماره موبایل مشتری"},
    *INVOICE_TEMPLATE_VARIABLES,
]

# رویدادهای تکمیلی ورک‌فلو — مهاجرت جدا برای نصب‌هایی که قبلاً seed اولیه را داشتند
WORKFLOW_EXTENSION_EVENT_CODES: frozenset[str] = frozenset(
    {
        "document.created",
        "person.created",
        "crm.lead.created",
        "crm.deal.closed",
        "inventory.low",
        "check.due_date",
        "distribution.visit.completed",
    }
)

INVOICE_SHARE_LINK_EVENT_CODES: frozenset[str] = frozenset({"invoice_share_link"})
PAY_LINK_RECEIVED_EVENT_CODES: frozenset[str] = frozenset({"pay_link.received"})
OFFICE_AUTOMATION_EVENT_CODES: frozenset[str] = frozenset(
	{
		"office_automation.letter_referred",
		"office_automation.letter_returned",
		"office_automation.letter_dispatched",
		"office_automation.letter_followup_due",
		"office_automation.letter_signed",
	}
)
INVENTORY_EXPIRY_EVENT_CODES: frozenset[str] = frozenset({"inventory.expires_soon"})

PAY_LINK_RECEIVED_TEMPLATE_VARIABLES: list[dict[str, str]] = [
    {"key": "payer_name", "type": "string", "description": "نام واریزکننده"},
    {"key": "amount", "type": "number", "description": "مبلغ واریز"},
    {"key": "date_time", "type": "string", "description": "تاریخ و ساعت واریز"},
    {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
    {"key": "username", "type": "string", "description": "نام کاربری لینک واریز"},
]

NOTIFICATION_EVENT_TYPES_ROWS: list[dict] = [
    {
        "code": "invoice.created",
        "name": "ثبت فاکتور (عمومی — ورک‌فلو)",
        "description": "با تریگر عمومی «invoice.created» در اتوماسیون؛ برای همه انواع فاکتور فعال می‌شود. برای فقط فروش یا فقط خرید، رویداد اختصاصی را انتخاب کنید.",
        "category": "sales",
        "available_variables": list(INVOICE_TEMPLATE_VARIABLES),
        "default_sms_template": "سلام {{ customer_name }} عزیز، فاکتور شماره {{ invoice_number }} به مبلغ {{ amount | format_currency }} برای شما ثبت شد. با تشکر، {{ business_name }}",
        "default_email_template": """سلام {{ customer_name }} عزیز،

فاکتور شماره {{ invoice_number }} به تاریخ {{ invoice_date | format_date }} برای شما ثبت شد.

مبلغ کل: {{ amount | format_currency }}
تاریخ سررسید: {{ due_date | format_date }}

با تشکر،
{{ business_name }}
تلفن: {{ business_phone }}""",
        "default_email_subject": "فاکتور جدید - {{ invoice_number }}",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "invoice.sales.created",
        "name": "ثبت فاکتور فروش",
        "description": "فقط هنگام ثبت فاکتور فروش (تریگر «invoice.sales.created» در ورک‌فلو).",
        "category": "sales",
        "available_variables": list(INVOICE_TEMPLATE_VARIABLES),
        "default_sms_template": "سلام {{ customer_name }} عزیز، فاکتور فروش {{ invoice_number }} به مبلغ {{ final_amount | format_currency }} ثبت شد. {{ business_name }}",
        "default_email_template": """سلام {{ customer_name }} عزیز،

فاکتور فروش {{ invoice_number }} به تاریخ {{ invoice_date | format_date }} ثبت شد.

مبلغ نهایی: {{ final_amount | format_currency }}

{{ business_name }} — {{ business_phone }}""",
        "default_email_subject": "فاکتور فروش جدید - {{ invoice_number }}",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "invoice.purchase.created",
        "name": "ثبت فاکتور خرید",
        "description": "فقط هنگام ثبت فاکتور خرید (تریگر «invoice.purchase.created»).",
        "category": "purchases",
        "available_variables": list(INVOICE_TEMPLATE_VARIABLES),
        "default_sms_template": "فاکتور خرید {{ invoice_number }} به مبلغ {{ final_amount | format_currency }} ثبت شد. طرف حساب: {{ customer_name }}. {{ business_name }}",
        "default_email_template": """فاکتور خرید {{ invoice_number }} — تاریخ {{ invoice_date | format_date }}

مبلغ نهایی: {{ final_amount | format_currency }}
طرف حساب: {{ customer_name }}

{{ business_name }}""",
        "default_email_subject": "فاکتور خرید - {{ invoice_number }}",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "receipt_payment.created",
        "name": "ثبت سند دریافت / پرداخت",
        "description": "هنگام ثبت سند دریافت یا پرداخت (تریگر «receipt_payment.created»).",
        "category": "financial",
        "available_variables": [
            {"key": "amount", "type": "number", "description": "مبلغ سند"},
            {"key": "payment_method", "type": "string", "description": "روش پرداخت (نقد، بانک، چک و …)"},
            {"key": "type", "type": "string", "description": "receipt یا payment"},
            {"key": "description", "type": "string", "description": "شرح سند"},
            {"key": "person_id", "type": "number", "description": "شناسه شخص در سند (در صورت وجود)"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
            {"key": "business_phone", "type": "string", "description": "تلفن کسب‌وکار"},
        ],
        "default_sms_template": "سند {{ type }} به مبلغ {{ amount | format_currency }} ثبت شد. {{ business_name }}",
        "default_email_template": """سند {{ type }} به مبلغ {{ amount | format_currency }} ثبت شد.

روش پرداخت: {{ payment_method }}
شرح: {{ description }}

{{ business_name }} — {{ business_phone }}""",
        "default_email_subject": "ثبت سند مالی — {{ business_name }}",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "crm.chat.message.received",
        "name": "پیام جدید در چت وب",
        "description": "وقتی بازدیدکننده پیامی در چت وب CRM ارسال می‌کند («crm.chat.message.received»).",
        "category": "crm",
        "available_variables": [
            {"key": "visitor_first_name", "type": "string", "description": "نام بازدیدکننده"},
            {"key": "visitor_last_name", "type": "string", "description": "نام خانوادگی"},
            {"key": "visitor_phone", "type": "string", "description": "تلفن بازدیدکننده"},
            {"key": "visitor_email", "type": "string", "description": "ایمیل"},
            {"key": "page_url", "type": "string", "description": "صفحه‌ای که چت از آن باز شده"},
            {"key": "conversation_status", "type": "string", "description": "وضعیت مکالمه"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
            {"key": "business_phone", "type": "string", "description": "تلفن کسب‌وکار"},
        ],
        "default_sms_template": "پیام جدید چت وب از {{ visitor_phone }} — {{ page_url }} — {{ business_name }}",
        "default_email_template": """پیام جدید در چت وب

نام: {{ visitor_first_name }} {{ visitor_last_name }}
تلفن: {{ visitor_phone }}
ایمیل: {{ visitor_email }}
صفحه: {{ page_url }}
وضعیت مکالمه: {{ conversation_status }}

{{ business_name }}""",
        "default_email_subject": "پیام جدید چت وب — {{ business_name }}",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "document.created",
        "name": "ثبت سند (عمومی)",
        "description": "پس از ایجاد سند حسابداری (هزینه/درآمد، سند دستی، …) با تریگر «document.created»؛ داده از غنی‌سازی سند پر می‌شود.",
        "category": "documents",
        "available_variables": [
            {"key": "document_id", "type": "number", "description": "شناسه سند"},
            {"key": "document_type", "type": "string", "description": "نوع سند"},
            {"key": "description", "type": "string", "description": "شرح سند"},
            {"key": "total_amount", "type": "number", "description": "جمع بدهکار سطرها (مبلغ کل)"},
            {"key": "is_proforma", "type": "string", "description": "پیش‌فاکتور بودن (true/false)"},
            {"key": "person_id", "type": "number", "description": "شناسه طرف‌حساب در صورت وجود"},
            {"key": "fiscal_year_id", "type": "number", "description": "شناسه سال مالی"},
            {"key": "project_id", "type": "number", "description": "شناسه پروژه در صورت وجود"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
            {"key": "business_phone", "type": "string", "description": "تلفن کسب‌وکار"},
        ],
        "default_sms_template": "سند {{ document_type }} ثبت شد (مبلغ {{ total_amount | format_currency }}). {{ business_name }}",
        "default_email_template": """سند {{ document_type }} ثبت شد.

مبلغ کل: {{ total_amount | format_currency }}
شرح: {{ description }}

{{ business_name }} — {{ business_phone }}""",
        "default_email_subject": "سند جدید — {{ business_name }}",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "person.created",
        "name": "ایجاد شخص جدید",
        "description": "با تریگر «person.created»؛ معمولاً فقط person_id و person_types در context است — نام را در ورک‌فلو با گره تکمیل داده اضافه کنید.",
        "category": "people",
        "available_variables": [
            {"key": "person_id", "type": "number", "description": "شناسه شخص جدید"},
            {"key": "person_types", "type": "string", "description": "انواع شخص (در ورک‌فلو به‌صورت داده ساختاریافته؛ در قالب متنی نمایش داده می‌شود)"},
            {"key": "person_name", "type": "string", "description": "نام نمایشی (در صورت افزودن در ورک‌فلو)"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
            {"key": "business_phone", "type": "string", "description": "تلفن کسب‌وکار"},
        ],
        "default_sms_template": "شخص جدید در {{ business_name }} ثبت شد (شناسه {{ person_id }}).",
        "default_email_template": """شخص جدید در {{ business_name }} ثبت شد.

شناسه: {{ person_id }}
نام: {{ person_name }}
انواع: {{ person_types }}

{{ business_name }} — {{ business_phone }}""",
        "default_email_subject": "شخص جدید — {{ business_name }}",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "crm.lead.created",
        "name": "ایجاد سرنخ CRM",
        "description": "تریگر «crm.lead.created» هنگام ایجاد سرنخ؛ فیلدها از trigger_data و غنی‌سازی Lead.",
        "category": "crm",
        "available_variables": [
            {"key": "lead_id", "type": "number", "description": "شناسه سرنخ"},
            {"key": "name", "type": "string", "description": "نام سرنخ (همان name اولیه)"},
            {"key": "lead_code", "type": "string", "description": "کد سرنخ"},
            {"key": "stage_name", "type": "string", "description": "نام مرحله فعلی"},
            {"key": "stage_code", "type": "string", "description": "کد مرحله"},
            {"key": "source_code", "type": "string", "description": "کد منبع"},
            {"key": "company_name", "type": "string", "description": "نام شرکت"},
            {"key": "mobile", "type": "string", "description": "موبایل"},
            {"key": "email", "type": "string", "description": "ایمیل"},
            {"key": "person_name", "type": "string", "description": "نام شخص مرتبط"},
            {"key": "assigned_to_user_name", "type": "string", "description": "نام کاربر مسئول"},
            {"key": "process_definition_name", "type": "string", "description": "نام فانل/فرایند"},
            {"key": "next_follow_up_at", "type": "date", "description": "زمان پیگیری بعدی (ISO)"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
            {"key": "business_phone", "type": "string", "description": "تلفن کسب‌وکار"},
        ],
        "default_sms_template": "سرنخ جدید {{ name }} — مرحله {{ stage_name }}. {{ business_name }}",
        "default_email_template": """سرنخ CRM جدید: {{ name }}

کد: {{ lead_code }}
مرحله: {{ stage_name }}
شرکت: {{ company_name }}
موبایل: {{ mobile }}

{{ business_name }}""",
        "default_email_subject": "سرنخ CRM جدید — {{ lead_code }}",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "crm.deal.closed",
        "name": "بستن معامله CRM",
        "description": "تریگر «crm.deal.closed»؛ شامل وضعیت برد/باخت و غنی‌سازی فرصت فروش.",
        "category": "crm",
        "available_variables": [
            {"key": "deal_id", "type": "number", "description": "شناسه فرصت"},
            {"key": "is_win", "type": "string", "description": "معامله موفق (true/false)"},
            {"key": "is_lost", "type": "string", "description": "از دست رفته (true/false)"},
            {"key": "amount", "type": "number", "description": "مبلغ در لحظه بستن"},
            {"key": "title", "type": "string", "description": "عنوان فرصت"},
            {"key": "deal_code", "type": "string", "description": "کد فرصت"},
            {"key": "stage_name", "type": "string", "description": "نام مرحله"},
            {"key": "person_name", "type": "string", "description": "نام مشتری مرتبط"},
            {"key": "probability_percent", "type": "number", "description": "درصد احتمال"},
            {"key": "document_id", "type": "number", "description": "شناسه سند مرتبط در صورت وجود"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
            {"key": "business_phone", "type": "string", "description": "تلفن کسب‌وکار"},
        ],
        "default_sms_template": "معامله {{ title }} بسته شد (برنده: {{ is_win }}). مبلغ {{ amount | format_currency }}. {{ business_name }}",
        "default_email_template": """معامله «{{ title }}» بسته شد.

کد: {{ deal_code }}
نتیجه: {{ is_win }}
مبلغ: {{ amount | format_currency }}
مشتری: {{ person_name }}

{{ business_name }}""",
        "default_email_subject": "بستن معامله — {{ deal_code }}",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "inventory.low",
        "name": "هشدار کمبود موجودی",
        "description": "وقتی موجودی کالا به نقطه سفارش (reorder) یا پایین‌تر برسد — «inventory.low».",
        "category": "warehouse",
        "available_variables": [
            {"key": "product_id", "type": "number", "description": "شناسه کالا"},
            {"key": "current_quantity", "type": "number", "description": "موجودی فعلی"},
            {"key": "min_quantity", "type": "number", "description": "حداقل / نقطه سفارش"},
            {"key": "warehouse_id", "type": "number", "description": "شناسه انبار در صورت وجود"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
            {"key": "business_phone", "type": "string", "description": "تلفن کسب‌وکار"},
        ],
        "default_sms_template": "هشدار موجودی: کالا {{ product_id }} به {{ current_quantity | format_number }} رسید (حد {{ min_quantity | format_number }}). {{ business_name }}",
        "default_email_template": """هشدار کمبود موجودی

کالا: {{ product_id }}
موجودی فعلی: {{ current_quantity | format_number }}
حداقل: {{ min_quantity | format_number }}

{{ business_name }} — {{ business_phone }}""",
        "default_email_subject": "کمبود موجودی — {{ business_name }}",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "inventory.expires_soon",
        "name": "هشدار نزدیک به انقضا",
        "description": "وقتی لات کالا به تاریخ هشدار یا انقضا برسد — «inventory.expires_soon».",
        "category": "warehouse",
        "available_variables": [
            {"key": "product_id", "type": "number", "description": "شناسه کالا"},
            {"key": "product_name", "type": "string", "description": "نام کالا"},
            {"key": "lot_code", "type": "string", "description": "کد لات"},
            {"key": "manufacturing_date", "type": "date", "description": "تاریخ تولید"},
            {"key": "expiry_date", "type": "date", "description": "تاریخ انقضا"},
            {"key": "remaining_days", "type": "number", "description": "روز مانده تا انقضا"},
            {"key": "quantity_main", "type": "number", "description": "مقدار در واحد اصلی"},
            {"key": "status", "type": "string", "description": "وضعیت لات"},
            {"key": "warehouse_id", "type": "number", "description": "شناسه انبار"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
        ],
        "default_sms_template": "هشدار انقضا: {{ product_name }} لات {{ lot_code }} تا {{ remaining_days | format_number }} روز دیگر منقضی می‌شود. {{ business_name }}",
        "default_email_template": """هشدار نزدیک به انقضا

کالا: {{ product_name }}
لات: {{ lot_code }}
تاریخ تولید: {{ manufacturing_date | format_date }}
تاریخ انقضا: {{ expiry_date | format_date }}
مانده: {{ remaining_days | format_number }} روز
مقدار: {{ quantity_main | format_number }}

{{ business_name }}""",
        "default_email_subject": "نزدیک به انقضا — {{ product_name }}",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "check.due_date",
        "name": "سررسید چک",
        "description": "یادآوری/اجرای ورک‌فلو برای چک نزدیک سررسید — «check.due_date».",
        "category": "financial",
        "available_variables": [
            {"key": "check_id", "type": "number", "description": "شناسه چک"},
            {"key": "check_number", "type": "string", "description": "شماره چک"},
            {"key": "amount", "type": "number", "description": "مبلغ چک"},
            {"key": "check_type", "type": "string", "description": "received یا paid"},
            {"key": "due_date", "type": "date", "description": "تاریخ سررسید (ISO)"},
            {"key": "days_until_due", "type": "number", "description": "تعداد روز تا سررسید (منفی یعنی گذشته)"},
            {"key": "person_id", "type": "number", "description": "شناسه طرف چک"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
            {"key": "business_phone", "type": "string", "description": "تلفن کسب‌وکار"},
        ],
        "default_sms_template": "چک {{ check_number }} به مبلغ {{ amount | format_currency }} — {{ days_until_due }} روز تا سررسید. {{ business_name }}",
        "default_email_template": """یادآوری سررسید چک

شماره چک: {{ check_number }}
مبلغ: {{ amount | format_currency }}
سررسید: {{ due_date | format_date }}
روزهای باقی‌مانده: {{ days_until_due }}

{{ business_name }}""",
        "default_email_subject": "سررسید چک {{ check_number }}",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "distribution.visit.completed",
        "name": "تکمیل ویزیت میدانی (پخش)",
        "description": "پس از تکمیل ویزیت در افزونه پخش مویرگی — «distribution.visit.completed».",
        "category": "distribution",
        "available_variables": [
            {"key": "visit_id", "type": "number", "description": "شناسه ویزیت"},
            {"key": "person_id", "type": "number", "description": "شناسه مشتری/مکان ویزیت"},
            {"key": "user_id", "type": "number", "description": "شناسه ویزیتور"},
            {"key": "route_id", "type": "number", "description": "شناسه مسیر"},
            {"key": "status", "type": "string", "description": "وضعیت ویزیت"},
            {"key": "outcome", "type": "string", "description": "نتیجه ویزیت"},
            {"key": "document_id", "type": "number", "description": "سند ایجادشده در صورت وجود"},
            {"key": "deal_id", "type": "number", "description": "فرصت فروش مرتبط"},
            {"key": "started_at", "type": "date", "description": "شروع ویزیت (ISO)"},
            {"key": "ended_at", "type": "date", "description": "پایان ویزیت (ISO)"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
            {"key": "business_phone", "type": "string", "description": "تلفن کسب‌وکار"},
        ],
        "default_sms_template": "ویزیت {{ visit_id }} برای مشتری {{ person_id }} تکمیل شد — {{ outcome }}. {{ business_name }}",
        "default_email_template": """ویزیت میدانی تکمیل شد

شناسه ویزیت: {{ visit_id }}
مشتری: {{ person_id }}
نتیجه: {{ outcome }}
وضعیت: {{ status }}

{{ business_name }}""",
        "default_email_subject": "ویزیت میدانی تکمیل شد — {{ business_name }}",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "repair_shop.received",
        "name": "دریافت کالا در تعمیرگاه",
        "description": "هنگامی که کالای مشتری برای تعمیر دریافت می‌شود",
        "category": "repair_shop",
        "available_variables": [
            {"key": "repair_code", "type": "string", "description": "کد رسید تعمیر"},
            {"key": "customer_name", "type": "string", "description": "نام مشتری"},
            {"key": "product_name", "type": "string", "description": "نام کالا"},
            {"key": "received_date", "type": "date", "description": "تاریخ دریافت"},
            {"key": "estimated_delivery", "type": "date", "description": "تاریخ تحویل تقریبی"},
            {"key": "business_name", "type": "string", "description": "نام تعمیرگاه"},
            {"key": "business_phone", "type": "string", "description": "تلفن تعمیرگاه"},
        ],
        "default_sms_template": "سلام {{ customer_name }} عزیز، {{ product_name }} شما با کد {{ repair_code }} دریافت شد. تاریخ تحویل تقریبی: {{ estimated_delivery | format_date }}. {{ business_name }}",
        "default_email_template": """سلام {{ customer_name }} عزیز،

{{ product_name }} شما با کد {{ repair_code }} دریافت شد.
تاریخ تحویل تقریبی: {{ estimated_delivery | format_date }}

{{ business_name }} — {{ business_phone }}""",
        "default_email_subject": "دریافت کالا - {{ repair_code }}",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "repair_shop.ready",
        "name": "آماده تحویل از تعمیرگاه",
        "description": "هنگامی که کالای تعمیر شده آماده تحویل است",
        "category": "repair_shop",
        "available_variables": [
            {"key": "repair_code", "type": "string", "description": "کد رسید تعمیر"},
            {"key": "customer_name", "type": "string", "description": "نام مشتری"},
            {"key": "product_name", "type": "string", "description": "نام کالا"},
            {"key": "final_cost", "type": "number", "description": "هزینه نهایی"},
            {"key": "status", "type": "string", "description": "وضعیت (تعمیر موفق/غیرقابل تعمیر)"},
            {"key": "business_name", "type": "string", "description": "نام تعمیرگاه"},
            {"key": "business_phone", "type": "string", "description": "تلفن تعمیرگاه"},
        ],
        "default_sms_template": "سلام {{ customer_name }}، {{ product_name }} شما (کد {{ repair_code }}) آماده تحویل است. هزینه: {{ final_cost | format_currency }}. {{ business_name }} - {{ business_phone }}",
        "default_email_template": """سلام {{ customer_name }}،

{{ product_name }} شما (کد {{ repair_code }}) آماده تحویل است.
هزینه نهایی: {{ final_cost | format_currency }}
وضعیت: {{ status }}

{{ business_name }} — {{ business_phone }}""",
        "default_email_subject": "کالای شما آماده تحویل است - {{ repair_code }}",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "payment.received",
        "name": "دریافت پرداخت",
        "description": "هنگامی که پرداختی از مشتری دریافت می‌شود",
        "category": "financial",
        "available_variables": [
            {"key": "receipt_number", "type": "string", "description": "شماره رسید"},
            {"key": "customer_name", "type": "string", "description": "نام پرداخت‌کننده"},
            {"key": "amount", "type": "number", "description": "مبلغ دریافتی"},
            {"key": "payment_date", "type": "date", "description": "تاریخ پرداخت"},
            {"key": "payment_method", "type": "string", "description": "روش پرداخت"},
            {"key": "remaining_balance", "type": "number", "description": "مانده حساب"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
        ],
        "default_sms_template": "سلام {{ customer_name }}، پرداخت شما به مبلغ {{ amount | format_currency }} با موفقیت دریافت شد. رسید: {{ receipt_number }}. با تشکر، {{ business_name }}",
        "default_email_template": """سلام {{ customer_name }}،

پرداخت شما به مبلغ {{ amount | format_currency }} با موفقیت دریافت شد.
شماره رسید: {{ receipt_number }}
تاریخ: {{ payment_date | format_date }}
روش پرداخت: {{ payment_method }}
مانده حساب: {{ remaining_balance | format_currency }}

با تشکر، {{ business_name }}""",
        "default_email_subject": "رسید پرداخت - {{ receipt_number }}",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "payment.reminder",
        "name": "یادآوری پرداخت",
        "description": "یادآوری سررسید پرداخت به مشتری",
        "category": "financial",
        "available_variables": [
            {"key": "customer_name", "type": "string", "description": "نام مشتری"},
            {"key": "invoice_number", "type": "string", "description": "شماره فاکتور"},
            {"key": "amount", "type": "number", "description": "مبلغ بدهی"},
            {"key": "due_date", "type": "date", "description": "تاریخ سررسید"},
            {"key": "days_overdue", "type": "number", "description": "تعداد روز تأخیر"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
            {"key": "business_phone", "type": "string", "description": "تلفن کسب‌وکار"},
        ],
        "default_sms_template": "سلام {{ customer_name }}، یادآوری: فاکتور {{ invoice_number }} به مبلغ {{ amount | format_currency }} در تاریخ {{ due_date | format_date }} سررسید دارد. {{ business_name }}",
        "default_email_template": """سلام {{ customer_name }}،

یادآوری پرداخت:
فاکتور {{ invoice_number }} به مبلغ {{ amount | format_currency }}
سررسید: {{ due_date | format_date }}
{% if days_overdue %}تأخیر: {{ days_overdue }} روز{% endif %}

{{ business_name }} — {{ business_phone }}""",
        "default_email_subject": "یادآوری سررسید پرداخت - {{ invoice_number }}",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "order.shipped",
        "name": "ارسال سفارش",
        "description": "هنگامی که سفارش مشتری ارسال می‌شود",
        "category": "sales",
        "available_variables": [
            {"key": "order_number", "type": "string", "description": "شماره سفارش"},
            {"key": "customer_name", "type": "string", "description": "نام مشتری"},
            {"key": "tracking_code", "type": "string", "description": "کد رهگیری"},
            {"key": "courier_name", "type": "string", "description": "نام پیک/پست"},
            {"key": "estimated_delivery", "type": "date", "description": "تاریخ تحویل تقریبی"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
        ],
        "default_sms_template": "سلام {{ customer_name }}، سفارش شما ({{ order_number }}) ارسال شد. کد رهگیری: {{ tracking_code }}. تحویل تقریبی: {{ estimated_delivery | format_date }}. {{ business_name }}",
        "default_email_template": """سلام {{ customer_name }}،

سفارش {{ order_number }} ارسال شد.
کد رهگیری: {{ tracking_code }}
پیک/پست: {{ courier_name }}
تحویل تقریبی: {{ estimated_delivery | format_date }}

{{ business_name }}""",
        "default_email_subject": "سفارش شما ارسال شد - {{ order_number }}",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "warranty.expires_soon",
        "name": "اتمام گارانتی",
        "description": "یادآوری اتمام گارانتی محصول",
        "category": "warranty",
        "available_variables": [
            {"key": "customer_name", "type": "string", "description": "نام مشتری"},
            {"key": "product_name", "type": "string", "description": "نام محصول"},
            {"key": "warranty_code", "type": "string", "description": "کد گارانتی"},
            {"key": "expiry_date", "type": "date", "description": "تاریخ اتمام"},
            {"key": "days_remaining", "type": "number", "description": "روزهای باقی‌مانده"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
            {"key": "business_phone", "type": "string", "description": "تلفن کسب‌وکار"},
        ],
        "default_sms_template": "سلام {{ customer_name }}، گارانتی {{ product_name }} شما (کد {{ warranty_code }}) در تاریخ {{ expiry_date | format_date }} به پایان می‌رسد. {{ business_name }}",
        "default_email_template": """سلام {{ customer_name }}،

گارانتی {{ product_name }} (کد {{ warranty_code }}) در تاریخ {{ expiry_date | format_date }} به پایان می‌رسد.
روزهای باقی‌مانده: {{ days_remaining }}

{{ business_name }} — {{ business_phone }}""",
        "default_email_subject": "یادآوری اتمام گارانتی - {{ product_name }}",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "person_share_link.sms",
        "name": "ارسال لینک کارت حساب به مشتری",
        "description": "ارسال لینک مشاهده کارت حساب (و در صورت تنظیم، فاکتورها) به مشتری از طریق پیامک",
        "category": "people",
        "available_variables": [
            {"key": "share_link", "type": "string", "description": "لینک کوتاه کارت حساب"},
            {"key": "customer_name", "type": "string", "description": "نام مشتری"},
            {"key": "customer_mobile", "type": "string", "description": "شماره موبایل مشتری"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
            {"key": "business_phone", "type": "string", "description": "تلفن کسب‌وکار"},
        ],
        "default_sms_template": "سلام {{ customer_name }}، لینک کارت حساب شما: {{ share_link }} — {{ business_name }}",
        "default_email_template": """سلام {{ customer_name }}،

لینک مشاهده کارت حساب شما:
{{ share_link }}

{{ business_name }} — {{ business_phone }}""",
        "default_email_subject": "لینک کارت حساب — {{ business_name }}",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "invoice_share_link",
        "name": "ارسال لینک فاکتور و پرداخت آنلاین",
        "description": "ارسال لینک مشاهده فاکتور و پرداخت آنلاین به مشتری (فروش سریع و اشتراک‌گذاری فاکتور)",
        "category": "sales",
        "available_variables": list(INVOICE_SHARE_LINK_TEMPLATE_VARIABLES),
        "default_sms_template": (
            "سلام {{ customer_name }}، فاکتور {{ invoice_number }} به مبلغ "
            "{{ final_amount | format_currency }}. لینک پرداخت: {{ share_link }} — {{ business_name }}"
        ),
        "default_email_template": """سلام {{ customer_name }} عزیز،

فاکتور {{ invoice_number }} به مبلغ {{ final_amount | format_currency }} برای شما صادر شد.

برای مشاهده و پرداخت آنلاین از لینک زیر استفاده کنید:
{{ share_link }}

{{ business_name }} — {{ business_phone }}""",
        "default_email_subject": "فاکتور {{ invoice_number }} — لینک پرداخت",
        "is_active": True,
        "requires_approval": True,
    },
    {
        "code": "pay_link.received",
        "name": "واریز از لینک پرداخت کسب‌وکار",
        "description": "اعلان مالک پس از واریز موفق از صفحه عمومی /u/{username}",
        "category": "sales",
        "available_variables": list(PAY_LINK_RECEIVED_TEMPLATE_VARIABLES),
        "default_sms_template": (
            "واریز {{ amount }} توسط {{ payer_name }} در {{ date_time }} "
            "از لینک {{ username }} — {{ business_name }}"
        ),
        "default_email_template": """واریز جدید از لینک پرداخت

مبلغ: {{ amount }}
واریزکننده: {{ payer_name }}
تاریخ: {{ date_time }}
لینک: {{ username }}

{{ business_name }}""",
        "default_email_subject": "واریز جدید از لینک پرداخت — {{ business_name }}",
        "is_active": True,
        "requires_approval": False,
    },
    {
        "code": "payroll.run.finalized",
        "name": "قطعی‌سازی اجرای حقوق",
        "description": "پس از قطعی‌سازی سند حقوق ماهانه",
        "category": "payroll",
        "available_variables": [
            {"key": "run_code", "type": "string", "description": "کد اجرای حقوق"},
            {"key": "period_title", "type": "string", "description": "عنوان دوره"},
            {"key": "net_total", "type": "number", "description": "جمع خالص پرداختی"},
            {"key": "employee_count", "type": "number", "description": "تعداد پرسنل"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
        ],
        "default_sms_template": "اجرای حقوق {{ run_code }} برای {{ period_title }} قطعی شد. جمع خالص: {{ net_total | format_currency }}. {{ business_name }}",
        "default_email_template": "اجرای حقوق {{ run_code }} برای دوره {{ period_title }} قطعی شد.\nتعداد پرسنل: {{ employee_count }}\nجمع خالص: {{ net_total | format_currency }}\n\n{{ business_name }}",
        "default_email_subject": "قطعی‌سازی حقوق — {{ period_title }}",
        "is_active": True,
        "requires_approval": False,
    },
    {
        "code": "payroll.run.posted",
        "name": "ثبت سند حسابداری حقوق",
        "description": "پس از صدور سند حسابداری حقوق",
        "category": "payroll",
        "available_variables": [
            {"key": "run_code", "type": "string", "description": "کد اجرای حقوق"},
            {"key": "document_code", "type": "string", "description": "شماره سند حسابداری"},
            {"key": "period_title", "type": "string", "description": "عنوان دوره"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
        ],
        "default_sms_template": "سند حسابداری حقوق {{ document_code }} برای {{ period_title }} ثبت شد. {{ business_name }}",
        "default_email_template": "سند حسابداری شماره {{ document_code }} برای اجرای حقوق {{ run_code }} ({{ period_title }}) ثبت شد.\n\n{{ business_name }}",
        "default_email_subject": "ثبت سند حسابداری حقوق — {{ document_code }}",
        "is_active": True,
        "requires_approval": False,
    },
    {
        "code": "office_automation.letter_referred",
        "name": "ارجاع نامه اتوماسیون اداری",
        "description": "پس از ارجاع نامه به کارتابل سمت",
        "category": "office_automation",
        "available_variables": [
            {"key": "subject", "type": "string", "description": "موضوع نامه"},
            {"key": "number", "type": "string", "description": "شماره دبیرخانه"},
            {"key": "letter_id", "type": "number", "description": "شناسه نامه"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
        ],
        "default_sms_template": "نامه «{{ subject }}» با شماره {{ number }} به کارتابل شما ارجاع شد. {{ business_name }}",
        "default_email_template": "نامه «{{ subject }}» با شماره {{ number }} به کارتابل شما ارجاع شد.\nشناسه نامه: {{ letter_id }}\n\n{{ business_name }}",
        "default_email_subject": "ارجاع نامه — {{ subject }}",
        "is_active": True,
        "requires_approval": False,
    },
    {
        "code": "office_automation.letter_returned",
        "name": "عودت نامه اتوماسیون اداری",
        "description": "پس از عودت ارجاع نامه به سمت فرستنده",
        "category": "office_automation",
        "available_variables": [
            {"key": "subject", "type": "string", "description": "موضوع نامه"},
            {"key": "number", "type": "string", "description": "شماره دبیرخانه"},
            {"key": "letter_id", "type": "number", "description": "شناسه نامه"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
        ],
        "default_sms_template": "نامه «{{ subject }}» با شماره {{ number }} به کارتابل شما عودت شد. {{ business_name }}",
        "default_email_template": "نامه «{{ subject }}» با شماره {{ number }} به کارتابل شما عودت شد.\nشناسه نامه: {{ letter_id }}\n\n{{ business_name }}",
        "default_email_subject": "عودت نامه — {{ subject }}",
        "is_active": True,
        "requires_approval": False,
    },
    {
        "code": "office_automation.letter_dispatched",
        "name": "ابلاغ نامه اتوماسیون اداری",
        "description": "پس از ابلاغ نامه به سمت مخاطب",
        "category": "office_automation",
        "available_variables": [
            {"key": "subject", "type": "string", "description": "موضوع نامه"},
            {"key": "number", "type": "string", "description": "شماره دبیرخانه"},
            {"key": "letter_id", "type": "number", "description": "شناسه نامه"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
        ],
        "default_sms_template": "نامه «{{ subject }}» با شماره {{ number }} به شما ابلاغ شد. {{ business_name }}",
        "default_email_template": "نامه «{{ subject }}» با شماره {{ number }} به شما ابلاغ شد.\nشناسه نامه: {{ letter_id }}\n\n{{ business_name }}",
        "default_email_subject": "ابلاغ نامه — {{ subject }}",
        "is_active": True,
        "requires_approval": False,
    },
    {
        "code": "office_automation.letter_followup_due",
        "name": "سررسید پیگیری نامه",
        "description": "هشدار سررسید تاریخ پیگیری نامه",
        "category": "office_automation",
        "available_variables": [
            {"key": "subject", "type": "string", "description": "موضوع نامه"},
            {"key": "number", "type": "string", "description": "شماره دبیرخانه"},
            {"key": "letter_id", "type": "number", "description": "شناسه نامه"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
        ],
        "default_sms_template": "پیگیری نامه «{{ subject }}» با شماره {{ number }} امروز سررسید شده است. {{ business_name }}",
        "default_email_template": "پیگیری نامه «{{ subject }}» با شماره {{ number }} امروز سررسید شده است.\nشناسه نامه: {{ letter_id }}\n\n{{ business_name }}",
        "default_email_subject": "سررسید پیگیری نامه — {{ subject }}",
        "is_active": True,
        "requires_approval": False,
    },
    {
        "code": "office_automation.letter_signed",
        "name": "امضای نامه اتوماسیون اداری",
        "description": "پس از امضای یک مرحله از مسیر امضا",
        "category": "office_automation",
        "available_variables": [
            {"key": "subject", "type": "string", "description": "موضوع نامه"},
            {"key": "number", "type": "string", "description": "شماره دبیرخانه"},
            {"key": "letter_id", "type": "number", "description": "شناسه نامه"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
        ],
        "default_sms_template": "نامه «{{ subject }}» با شماره {{ number }} امضا شد. {{ business_name }}",
        "default_email_template": "نامه «{{ subject }}» با شماره {{ number }} امضا شد.\nشناسه نامه: {{ letter_id }}\n\n{{ business_name }}",
        "default_email_subject": "امضای نامه — {{ subject }}",
        "is_active": True,
        "requires_approval": False,
    },
    {
        "code": "procurement.requisition.approved",
        "name": "تأیید درخواست خرید",
        "description": "پس از تأیید نهایی درخواست خرید",
        "category": "procurement",
        "available_variables": [
            {"key": "code", "type": "string", "description": "شماره درخواست"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
        ],
        "default_sms_template": "درخواست خرید {{ code }} تأیید شد. {{ business_name }}",
        "default_email_template": "درخواست خرید {{ code }} تأیید شد.\n\n{{ business_name }}",
        "default_email_subject": "تأیید درخواست خرید — {{ code }}",
        "is_active": True,
        "requires_approval": False,
    },
    {
        "code": "procurement.order.approved",
        "name": "تأیید سفارش خرید",
        "description": "پس از تأیید سفارش خرید",
        "category": "procurement",
        "available_variables": [
            {"key": "code", "type": "string", "description": "شماره سفارش"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
        ],
        "default_sms_template": "سفارش خرید {{ code }} تأیید شد. {{ business_name }}",
        "default_email_template": "سفارش خرید {{ code }} تأیید شد.\n\n{{ business_name }}",
        "default_email_subject": "تأیید سفارش خرید — {{ code }}",
        "is_active": True,
        "requires_approval": False,
    },
    {
        "code": "procurement.contract.expiring",
        "name": "نزدیک شدن انقضای قرارداد تأمین",
        "description": "وقتی قرارداد فعال در ۳۰ روز آینده تمام می‌شود",
        "category": "procurement",
        "available_variables": [
            {"key": "code", "type": "string", "description": "شماره قرارداد"},
            {"key": "end_date", "type": "string", "description": "تاریخ پایان"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
        ],
        "default_sms_template": "قرارداد {{ code }} در تاریخ {{ end_date }} تمام می‌شود. {{ business_name }}",
        "default_email_template": "قرارداد {{ code }} در تاریخ {{ end_date }} به پایان می‌رسد.\n\n{{ business_name }}",
        "default_email_subject": "انقضای قرارداد تأمین — {{ code }}",
        "is_active": True,
        "requires_approval": False,
    },
]


PROCUREMENT_EVENT_CODES: frozenset[str] = frozenset(
    {
        "procurement.requisition.approved",
        "procurement.order.approved",
        "procurement.contract.expiring",
    }
)


def event_type_row_by_code(code: str) -> dict | None:
    """برگرداندن ردیف seed برای یک code (برای مهاجرت و تست)."""
    for row in NOTIFICATION_EVENT_TYPES_ROWS:
        if row["code"] == code:
            return row
    return None
