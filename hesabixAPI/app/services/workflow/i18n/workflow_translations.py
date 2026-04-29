"""
سیستم ترجمه برای نودهای ورک‌فلو
این ماژول رشته‌های قابل ترجمه برای metadata نودها را مدیریت می‌کند
"""
import copy
from typing import Dict, Any
from enum import Enum

from .hesabix_data_actions_i18n import (
    WORKFLOW_ACTION_TRANSLATIONS,
    get_workflow_action_keys,
)
from .lifecycle_triggers_i18n import (
    INVOICE_WORKFLOW_TRIGGER_TRANSLATIONS,
    INVOICE_WORKFLOW_TRIGGER_UPDATED_TRANSLATIONS,
    PERSON_WORKFLOW_TRIGGER_TRANSLATIONS,
    PERSON_WORKFLOW_TRIGGER_UPDATED_TRANSLATIONS,
)
from .crm_chat_triggers_i18n import (
    CRM_CHAT_CONVERSATION_ASSIGNED_TRANSLATIONS,
    CRM_CHAT_CONVERSATION_REOPENED_TRANSLATIONS,
    CRM_CHAT_CONVERSATION_RESOLVED_TRANSLATIONS,
    CRM_CHAT_CONVERSATION_STARTED_TRANSLATIONS,
    CRM_CHAT_MESSAGE_RECEIVED_TRANSLATIONS,
    CRM_CHAT_MESSAGE_SENT_TRANSLATIONS,
)


class SupportedLanguage(str, Enum):
    """زبان‌های پشتیبانی شده"""
    FA = "fa"  # فارسی
    EN = "en"  # انگلیسی


# ترجمه‌های مشترک
COMMON_TRANSLATIONS = {
    "fa": {
        # عناوین عمومی
        "settings": "تنظیمات",
        "basic_info": "اطلاعات پایه",
        "advanced": "پیشرفته",
        "required_field": "این فیلد الزامی است",
        "optional": "اختیاری",
        "yes": "بله",
        "no": "خیر",
        
        # انواع داده
        "string": "متن",
        "number": "عدد",
        "integer": "عدد صحیح",
        "boolean": "بله/خیر",
        "array": "لیست",
        "object": "شیء",
        "date": "تاریخ",
        
        # دسته‌بندی نودها
        "category_financial": "مالی و حسابداری",
        "category_communication": "ارتباطات",
        "category_utility": "ابزارها",
        "category_inventory": "انبار و موجودی",
        "category_data": "داده و اطلاعات",
    },
    "en": {
        # عناوین عمومی
        "settings": "Settings",
        "basic_info": "Basic Information",
        "advanced": "Advanced",
        "required_field": "This field is required",
        "optional": "Optional",
        "yes": "Yes",
        "no": "No",
        
        # انواع داده
        "string": "Text",
        "number": "Number",
        "integer": "Integer",
        "boolean": "Yes/No",
        "array": "List",
        "object": "Object",
        "date": "Date",
        
        # دسته‌بندی نودها
        "category_financial": "Financial & Accounting",
        "category_communication": "Communication",
        "category_utility": "Utilities",
        "category_inventory": "Inventory & Warehouse",
        "category_data": "Data & Information",
    }
}


# ترجمه‌های اکشن "ایجاد فاکتور"
CREATE_INVOICE_TRANSLATIONS = {
    "fa": {
        "action_name": "ایجاد فاکتور",
        "action_description": "ایجاد فاکتور فروش، خرید یا برگشتی با امکانات پیشرفته",
        
        # گروه‌ها
        "group_basic_info": "اطلاعات پایه",
        "group_items": "آیتم‌های فاکتور",
        "group_financial": "تنظیمات مالی",
        "group_payment": "پرداخت",
        "group_warehouse": "انبار",
        "group_advanced": "پیشرفته",
        
        # فیلد invoice_type
        "field_invoice_type": "نوع فاکتور",
        "field_invoice_type_desc": "نوع فاکتور",
        "invoice_sales": "فاکتور فروش",
        "invoice_purchase": "فاکتور خرید",
        "invoice_return_sales": "برگشت از فروش",
        "invoice_return_purchase": "برگشت از خرید",
        
        # فیلد person_id
        "field_person_id": "طرف حساب",
        "field_person_id_desc": "شناسه طرف حساب (مشتری یا تأمین‌کننده) - می‌توانید از نودهای قبلی استفاده کنید: $node_id.person_id",
        
        # فیلد document_date
        "field_document_date": "تاریخ فاکتور",
        "field_document_date_desc": "تاریخ فاکتور (ISO format: YYYY-MM-DD) - پیش‌فرض: امروز. می‌توانید از نودهای قبلی استفاده کنید: $node_id.date",
        
        # فیلد description
        "field_description": "توضیحات",
        "field_description_desc": "توضیحات فاکتور - می‌توانید از نودهای قبلی استفاده کنید: فاکتور برای $node_id.customer_name",
        "field_description_placeholder": "توضیحات فاکتور را وارد کنید...",
        
        # فیلد currency_id
        "field_currency_id": "ارز",
        "field_currency_id_desc": "شناسه ارز (پیش‌فرض: ارز کسب‌وکار)",
        
        # فیلد items
        "field_items": "آیتم‌ها",
        "field_items_desc": "آیتم‌های فاکتور - می‌توانید به صورت دستی یا از نودهای قبلی استفاده کنید: $node_id.items",
        "field_items_help": "محصولات فاکتور را اضافه کنید. می‌توانید از reference به نودهای قبلی استفاده کنید: $node_id.items",
        "item_product_id": "محصول",
        "item_quantity": "تعداد",
        "item_unit_price": "قیمت واحد",
        "item_unit_price_desc": "قیمت واحد (پیش‌فرض: قیمت محصول)",
        "item_discount_percent": "درصد تخفیف",
        "item_tax_percent": "درصد مالیات",
        "item_description": "توضیحات آیتم",
        
        # فیلد discount
        "field_discount": "تخفیف کلی",
        "field_discount_desc": "تخفیف کلی فاکتور (اختیاری)",
        "discount_type": "نوع تخفیف",
        "discount_type_percent": "درصدی",
        "discount_type_fixed": "مبلغ ثابت",
        "discount_value": "مقدار تخفیف",
        
        # فیلد tax_config
        "field_tax_config": "تنظیمات مالیاتی",
        "field_tax_config_desc": "تنظیمات مالیاتی (اختیاری)",
        "tax_apply": "اعمال مالیات",
        "tax_rate": "نرخ مالیات (درصد)",
        "tax_included": "مالیات جزو قیمت است",
        
        # فیلد payments
        "field_auto_create_payment": "ایجاد خودکار پرداخت",
        "field_auto_create_payment_desc": "ایجاد خودکار سند پرداخت/دریافت",
        "field_payments": "پرداخت‌ها",
        "field_payments_desc": "پرداخت‌های همزمان با فاکتور (اختیاری)",
        "field_payments_help": "برای ثبت پرداخت همزمان با فاکتور، این بخش را فعال کنید",
        "payment_amount": "مبلغ پرداخت",
        "payment_method": "روش پرداخت",
        "payment_method_cash": "نقد",
        "payment_method_bank": "بانک",
        "payment_method_check": "چک",
        "payment_method_card": "کارت",
        "payment_account": "حساب بانکی/صندوق",
        "payment_description": "توضیحات پرداخت",
        
        # فیلد warehouse
        "field_warehouse_settings": "تنظیمات انبار",
        "field_warehouse_settings_desc": "تنظیمات انبار و حواله (اختیاری)",
        "field_warehouse_settings_help": "در صورت فعال بودن، حواله انبار به صورت خودکار ایجاد می‌شود",
        "warehouse_create_document": "ایجاد خودکار حواله",
        "warehouse_id": "انبار مبدأ/مقصد",
        "warehouse_auto_post": "ثبت خودکار حواله",
        
        # فیلدهای پیشرفته
        "field_is_proforma": "پیش‌فاکتور",
        "field_is_proforma_desc": "پیش‌فاکتور (بدون تأثیر حسابداری)",
        "field_is_proforma_help": "پیش‌فاکتور بر روی حسابداری و موجودی تأثیر نمی‌گذارد",
        "field_fiscal_year_id": "سال مالی",
        "field_fiscal_year_id_desc": "سال مالی (پیش‌فرض: سال جاری)",
        "field_reference_code": "کد مرجع",
        "field_reference_code_desc": "کد/شماره مرجع (اختیاری)",
        "field_extra_info": "اطلاعات اضافی",
        "field_extra_info_desc": "اطلاعات اضافی (JSON - اختیاری)",
        
        # پیام‌های خطا
        "error_min_items": "حداقل یک آیتم باید وارد شود",
        "error_max_items": "حداکثر 100 آیتم مجاز است",
        "error_date_fiscal_year": "تاریخ باید در محدوده سال مالی فعال باشد",
    },
    "en": {
        "action_name": "Create Invoice",
        "action_description": "Create sales, purchase or return invoice with advanced features",
        
        # گروه‌ها
        "group_basic_info": "Basic Information",
        "group_items": "Invoice Items",
        "group_financial": "Financial Settings",
        "group_payment": "Payment",
        "group_warehouse": "Warehouse",
        "group_advanced": "Advanced",
        
        # فیلد invoice_type
        "field_invoice_type": "Invoice Type",
        "field_invoice_type_desc": "Invoice Type",
        "invoice_sales": "Sales Invoice",
        "invoice_purchase": "Purchase Invoice",
        "invoice_return_sales": "Sales Return",
        "invoice_return_purchase": "Purchase Return",
        
        # فیلد person_id
        "field_person_id": "Contact",
        "field_person_id_desc": "Contact ID (customer or supplier) - You can use previous nodes: $node_id.person_id",
        
        # فیلد document_date
        "field_document_date": "Invoice Date",
        "field_document_date_desc": "Invoice date (ISO format: YYYY-MM-DD) - Default: today. You can use previous nodes: $node_id.date",
        
        # فیلد description
        "field_description": "Description",
        "field_description_desc": "Invoice description - You can use previous nodes: Invoice for $node_id.customer_name",
        "field_description_placeholder": "Enter invoice description...",
        
        # فیلد currency_id
        "field_currency_id": "Currency",
        "field_currency_id_desc": "Currency ID (default: business currency)",
        
        # فیلد items
        "field_items": "Items",
        "field_items_desc": "Invoice items - You can manually add or use previous nodes: $node_id.items",
        "field_items_help": "Add invoice products. You can use references to previous nodes: $node_id.items",
        "item_product_id": "Product",
        "item_quantity": "Quantity",
        "item_unit_price": "Unit Price",
        "item_unit_price_desc": "Unit price (default: product price)",
        "item_discount_percent": "Discount %",
        "item_tax_percent": "Tax %",
        "item_description": "Item Description",
        
        # فیلد discount
        "field_discount": "Global Discount",
        "field_discount_desc": "Global invoice discount (optional)",
        "discount_type": "Discount Type",
        "discount_type_percent": "Percentage",
        "discount_type_fixed": "Fixed Amount",
        "discount_value": "Discount Value",
        
        # فیلد tax_config
        "field_tax_config": "Tax Settings",
        "field_tax_config_desc": "Tax configuration (optional)",
        "tax_apply": "Apply Tax",
        "tax_rate": "Tax Rate (%)",
        "tax_included": "Tax Included in Price",
        
        # فیلد payments
        "field_auto_create_payment": "Auto Create Payment",
        "field_auto_create_payment_desc": "Automatically create payment/receipt document",
        "field_payments": "Payments",
        "field_payments_desc": "Payments along with invoice (optional)",
        "field_payments_help": "Enable to record payment simultaneously with invoice",
        "payment_amount": "Payment Amount",
        "payment_method": "Payment Method",
        "payment_method_cash": "Cash",
        "payment_method_bank": "Bank",
        "payment_method_check": "Check",
        "payment_method_card": "Card",
        "payment_account": "Bank/Cash Account",
        "payment_description": "Payment Description",
        
        # فیلد warehouse
        "field_warehouse_settings": "Warehouse Settings",
        "field_warehouse_settings_desc": "Warehouse and transfer settings (optional)",
        "field_warehouse_settings_help": "When enabled, warehouse document is automatically created",
        "warehouse_create_document": "Auto Create Transfer",
        "warehouse_id": "Warehouse (Source/Destination)",
        "warehouse_auto_post": "Auto Post Transfer",
        
        # فیلدهای پیشرفته
        "field_is_proforma": "Proforma Invoice",
        "field_is_proforma_desc": "Proforma invoice (no accounting impact)",
        "field_is_proforma_help": "Proforma invoices don't affect accounting and inventory",
        "field_fiscal_year_id": "Fiscal Year",
        "field_fiscal_year_id_desc": "Fiscal year (default: current year)",
        "field_reference_code": "Reference Code",
        "field_reference_code_desc": "Reference code/number (optional)",
        "field_extra_info": "Extra Information",
        "field_extra_info_desc": "Additional information (JSON - optional)",
        
        # پیام‌های خطا
        "error_min_items": "At least one item is required",
        "error_max_items": "Maximum 100 items allowed",
        "error_date_fiscal_year": "Date must be within active fiscal year",
    }
}


# ترجمه‌های اکشن "ارسال بله"
SEND_BALE_TRANSLATIONS = {
    "fa": {
        "action_name": "ارسال پیام به بله",
        "action_description": "ارسال متن و/یا فایل (مثلاً پشتیبان از نود قبلی) به کاربر متصل به ربات بله",
        # برچسب فیلدها
        "field_user_id": "کاربر گیرنده",
        "field_send_file_attachment": "ارسال فایل",
        "field_attachment_file_id": "شناسه فایل (ذخیره‌شده)",
        "field_message": "متن / زیرنویس فایل",
        "field_parse_mode": "حالت پارس متن",
        "field_retry_on_failure": "تلاش مجدد در صورت خطا",
        "field_retry_attempts": "تعداد تلاش‌های مجدد",
        "field_retry_delay_seconds": "تاخیر بین تلاش‌ها",
        # توضیحات فیلدها
        "field_user_id_desc": "شناسه کاربر عضو کسب و کار که به ربات بله متصل است (می‌تواند از نودهای قبلی باشد: $node_id.user_id)",
        "field_send_file_attachment_desc": "اگر روشن باشد، فایل از فایل‌سرور با sendDocument ارسال می‌شود (نه فقط متن)",
        "field_attachment_file_id_desc": "شناسه UUID فایل؛ پس از نود پشتیبان معمولاً $همان_نود.file_id یا $همان_نود.attachment_file_id",
        "field_message_desc": "متن پیام؛ در حالت ارسال فایل به‌عنوان زیرنویس (caption) استفاده می‌شود و می‌تواند خالی باشد",
        "field_parse_mode_desc": "حالت پارس متن (متن ساده، HTML یا Markdown)",
        "field_retry_on_failure_desc": "تلاش مجدد در صورت شکست ارسال",
        "field_retry_attempts_desc": "تعداد تلاش‌های مجدد",
        "field_retry_delay_seconds_desc": "تاخیر بین تلاش‌ها (ثانیه)",
        # placeholder
        "field_message_placeholder": "متن پیام را وارد کنید...",
        # enum parse_mode
        "None": "متن ساده",
        "HTML": "HTML - با فرمت اچ‌تی‌ام‌ال",
        "Markdown": "Markdown - با فرمت مارک‌داون",
    },
    "en": {
        "action_name": "Send Bale Message",
        "action_description": "Send text and/or a file (e.g. backup from previous node) via Bale",
        # Field labels
        "field_user_id": "Recipient User",
        "field_send_file_attachment": "Send file",
        "field_attachment_file_id": "Stored file ID",
        "field_message": "Text / file caption",
        "field_parse_mode": "Parse Mode",
        "field_retry_on_failure": "Retry on Failure",
        "field_retry_attempts": "Retry Attempts",
        "field_retry_delay_seconds": "Retry Delay",
        # Field descriptions
        "field_user_id_desc": "User ID of business member connected to Bale bot (can use previous nodes: $node_id.user_id)",
        "field_send_file_attachment_desc": "If enabled, sends a file via sendDocument from file storage",
        "field_attachment_file_id_desc": "File UUID; after backup node use e.g. $that_node.file_id",
        "field_message_desc": "Message text; when sending a file, used as caption (can be empty)",
        "field_parse_mode_desc": "Parse mode (plain text, HTML or Markdown)",
        "field_retry_on_failure_desc": "Retry on send failure",
        "field_retry_attempts_desc": "Number of retry attempts",
        "field_retry_delay_seconds_desc": "Delay between retries (seconds)",
        # Placeholder
        "field_message_placeholder": "Enter your message...",
        # enum parse_mode
        "None": "Plain text",
        "HTML": "HTML",
        "Markdown": "Markdown",
    }
}


SEND_TELEGRAM_TRANSLATIONS = {
    "fa": {
        "action_name": "ارسال پیام تلگرام",
        "action_description": "ارسال پیام به کاربر عضو کسب و کار از طریق تلگرام (فقط کاربران متصل به ربات)",
        
        "field_user_id": "کاربر دریافت‌کننده",
        "field_user_id_desc": "شناسه کاربر عضو کسب و کار که به ربات تلگرام متصل است (می‌تواند از نودهای قبلی باشد: $node_id.user_id)",
        
        "field_message": "متن پیام",
        "field_message_desc": "متن پیام ارسالی به کاربر",
        "field_message_placeholder": "متن پیام خود را وارد کنید...",
        
        "field_parse_mode": "حالت پارس متن",
        "field_parse_mode_desc": "حالت پارس متن (متن ساده، HTML یا Markdown)",
        # enum parse_mode
        "None": "متن ساده",
        "HTML": "HTML - با فرمت اچ‌تی‌ام‌ال",
        "Markdown": "Markdown - با فرمت مارک‌داون",
        
        "field_disable_web_page_preview": "غیرفعال کردن پیش‌نمایش لینک",
        "field_disable_web_page_preview_desc": "غیرفعال کردن پیش‌نمایش لینک",
        
        "field_retry_on_failure": "تلاش مجدد در صورت خطا",
        "field_retry_on_failure_desc": "تلاش مجدد در صورت شکست ارسال",
        
        "field_retry_attempts": "تعداد تلاش‌های مجدد",
        "field_retry_attempts_desc": "تعداد تلاش‌های مجدد",
        
        "field_retry_delay_seconds": "تاخیر بین تلاش‌ها",
        "field_retry_delay_seconds_desc": "تاخیر بین تلاش‌ها (ثانیه)",
    },
    "en": {
        "action_name": "Send Telegram Message",
        "action_description": "Send message to business member via Telegram (only connected users)",
        
        "field_user_id": "Recipient User",
        "field_user_id_desc": "User ID of business member connected to Telegram bot (can use previous nodes: $node_id.user_id)",
        
        "field_message": "Message Text",
        "field_message_desc": "Message text to send to user",
        "field_message_placeholder": "Enter your message...",
        
        "field_parse_mode": "Parse Mode",
        "field_parse_mode_desc": "Parse mode (plain text, HTML or Markdown)",
        # enum parse_mode
        "None": "Plain text",
        "HTML": "HTML",
        "Markdown": "Markdown",
        
        "field_disable_web_page_preview": "Disable Web Page Preview",
        "field_disable_web_page_preview_desc": "Disable web page preview",
        
        "field_retry_on_failure": "Retry on Failure",
        "field_retry_on_failure_desc": "Retry on send failure",
        
        "field_retry_attempts": "Retry Attempts",
        "field_retry_attempts_desc": "Number of retry attempts",
        
        "field_retry_delay_seconds": "Retry Delay",
        "field_retry_delay_seconds_desc": "Delay between retries (seconds)",
    }
}


# ترجمه‌های اکشن "ارسال ایمیل"
SEND_EMAIL_TRANSLATIONS = {
    "fa": {
        "action_name": "ارسال ایمیل",
        "action_description": "ارسال ایمیل به آدرس مشخص",
        
        "field_to": "گیرنده",
        "field_to_desc": "آدرس ایمیل گیرنده (می‌تواند از نودهای قبلی باشد: $node_id.email)",
        
        "field_cc": "رونوشت",
        "field_cc_desc": "آدرس‌های ایمیل برای رونوشت (CC)",
        
        "field_bcc": "رونوشت مخفی",
        "field_bcc_desc": "آدرس‌های ایمیل برای رونوشت مخفی (BCC)",
        
        "field_subject": "موضوع",
        "field_subject_desc": "موضوع ایمیل (می‌تواند از نودهای قبلی باشد)",
        
        "field_body": "متن ایمیل",
        "field_body_desc": "متن ایمیل (plain text)",
        
        "field_html_body": "متن HTML",
        "field_html_body_desc": "متن ایمیل (HTML - اختیاری)",
        
        "field_retry_on_failure": "تلاش مجدد در صورت خطا",
        "field_retry_attempts": "تعداد تلاش‌های مجدد",
        "field_retry_delay_seconds": "تاخیر بین تلاش‌ها (ثانیه)",
    },
    "en": {
        "action_name": "Send Email",
        "action_description": "Send email to specified address",
        
        "field_to": "To",
        "field_to_desc": "Recipient email address (can use previous nodes: $node_id.email)",
        
        "field_cc": "CC",
        "field_cc_desc": "Email addresses for carbon copy (CC)",
        
        "field_bcc": "BCC",
        "field_bcc_desc": "Email addresses for blind carbon copy (BCC)",
        
        "field_subject": "Subject",
        "field_subject_desc": "Email subject (can use previous nodes)",
        
        "field_body": "Body",
        "field_body_desc": "Email body (plain text)",
        
        "field_html_body": "HTML Body",
        "field_html_body_desc": "Email body (HTML - optional)",
        
        "field_retry_on_failure": "Retry on Failure",
        "field_retry_attempts": "Retry Attempts",
        "field_retry_delay_seconds": "Retry Delay (seconds)",
    }
}


# ترجمه‌های اکشن AI Agent
AI_AGENT_TRANSLATIONS = {
    "fa": {
        "action_name": "AI Agent",
        "action_description": "عامل هوشمند برای تولید متن، تصمیم‌گیری، فراخوانی توابع و خروجی ساختاریافته. مشابه n8n AI Agent.",
        # برچسب‌های فیلدها
        "field_system_prompt": "دستورات سیستم",
        "field_user_prompt": "دستور/سوال کاربر",
        "field_tools_mode": "حالت ابزارها",
        "field_tools_category": "دسته توابع",
        "field_tools_allowlist": "توابع مجاز",
        "field_tools_denylist": "توابع غیرمجاز",
        "field_max_iterations": "حداکثر چرخه",
        "field_temperature": "دما",
        "field_max_tokens": "حداکثر توکن",
        "field_output_mode": "نوع خروجی",
        "field_inject_trigger_data": "افزودن trigger_data",
        "field_inject_node_results": "افزودن نتایج نودها",
        # توضیحات فیلدها
        "field_system_prompt_desc": "دستورات سیستم برای AI (وظیفه، قوانین، قالب خروجی)",
        "field_user_prompt_desc": "سوال یا دستور برای AI. می‌توانید از $trigger_1، $node_id و {{ trigger_data.field }} استفاده کنید.",
        "field_tools_mode_desc": "حالت ابزارها (توابع قابل فراخوانی توسط AI)",
        "field_tools_category_desc": "دسته توابع (در حالت category)",
        "field_tools_allowlist_desc": "لیست توابع مجاز جدا شده با کاما (در حالت custom)",
        "field_tools_denylist_desc": "لیست توابع غیرمجاز جدا شده با کاما",
        "field_max_iterations_desc": "حداکثر چرخه فراخوانی توابع (برای multi-step reasoning)",
        "field_temperature_desc": "دما (0 برای تصمیم‌گیری دقیق، بالاتر برای خلاقیت)",
        "field_max_tokens_desc": "حداکثر توکن خروجی",
        "field_output_mode_desc": "نوع خروجی",
        "field_inject_trigger_data_desc": "اضافه کردن trigger_data به context",
        "field_inject_node_results_desc": "اضافه کردن نتایج نودهای قبلی به context",
        # placeholders
        "field_system_prompt_placeholder": "دستورات و قوانین AI را وارد کنید...",
        "field_user_prompt_placeholder": "سوال یا دستور را وارد کنید. از $trigger_1 استفاده کنید...",
        "field_tools_allowlist_placeholder": "مثال: search_invoices, get_invoice_details",
        "field_tools_denylist_placeholder": "مثال: create_invoice",
        # enum tools_mode
        "all": "همه توابع",
        "category": "بر اساس دسته",
        "custom": "لیست سفارشی",
        "none": "بدون توابع",
        # enum output_mode
        "text": "متن",
        "json": "JSON",
        # enum tools_category
        "invoices": "فاکتورها",
        "persons": "اشخاص",
        "products": "محصولات",
        "financial": "مالی",
        "crm": "CRM",
        "business": "کسب‌وکار",
    },
    "en": {
        "action_name": "AI Agent",
        "action_description": "Intelligent agent for text generation, decision making, function calling and structured output. Similar to n8n AI Agent.",
        # Field labels
        "field_system_prompt": "System Instructions",
        "field_user_prompt": "User Prompt/Question",
        "field_tools_mode": "Tools Mode",
        "field_tools_category": "Tools Category",
        "field_tools_allowlist": "Allowed Functions",
        "field_tools_denylist": "Denied Functions",
        "field_max_iterations": "Max Iterations",
        "field_temperature": "Temperature",
        "field_max_tokens": "Max Tokens",
        "field_output_mode": "Output Mode",
        "field_inject_trigger_data": "Inject Trigger Data",
        "field_inject_node_results": "Inject Node Results",
        # Field descriptions
        "field_system_prompt_desc": "System instructions for AI (task, rules, output format)",
        "field_user_prompt_desc": "Question or instruction for AI. Use $trigger_1, $node_id and {{ trigger_data.field }}",
        "field_tools_mode_desc": "Tools mode (functions AI can call)",
        "field_tools_category_desc": "Tools category (when mode is category)",
        "field_tools_allowlist_desc": "Comma-separated list of allowed functions (when mode is custom)",
        "field_tools_denylist_desc": "Comma-separated list of denied functions",
        "field_max_iterations_desc": "Maximum function call iterations (for multi-step reasoning)",
        "field_temperature_desc": "Temperature (0 for precise decisions, higher for creativity)",
        "field_max_tokens_desc": "Maximum output tokens",
        "field_output_mode_desc": "Output type",
        "field_inject_trigger_data_desc": "Add trigger_data to context",
        "field_inject_node_results_desc": "Add previous node results to context",
        # Placeholders
        "field_system_prompt_placeholder": "Enter AI instructions and rules...",
        "field_user_prompt_placeholder": "Enter question or instruction. Use $trigger_1...",
        "field_tools_allowlist_placeholder": "e.g.: search_invoices, get_invoice_details",
        "field_tools_denylist_placeholder": "e.g.: create_invoice",
        # enum tools_mode
        "all": "All functions",
        "category": "By category",
        "custom": "Custom list",
        "none": "No functions",
        # enum output_mode
        "text": "Text",
        "json": "JSON",
        # enum tools_category
        "invoices": "Invoices",
        "persons": "Persons",
        "products": "Products",
        "financial": "Financial",
        "crm": "CRM",
        "business": "Business",
    }
}


# ترجمه‌های سایر اکشن‌ها
OTHER_ACTIONS_TRANSLATIONS = {
    "fa": {
        # Create Notification
        "create_notification_name": "ایجاد اعلان",
        "create_notification_desc": "ایجاد یک اعلان برای کاربر",
        
        # Set Variable
        "set_variable_name": "تنظیم متغیر",
        "set_variable_desc": "تنظیم یک متغیر در context برای استفاده در نودهای بعدی",
        
        # Log
        "log_name": "ثبت لاگ",
        "log_desc": "ثبت یک لاگ در workflow execution",
        
        # HTTP Request
        "http_request_name": "درخواست HTTP",
        "http_request_desc": "ارسال یک درخواست HTTP به URL مشخص",
        
        # Create Document
        "create_document_name": "ایجاد سند",
        "create_document_desc": "ایجاد یک سند حسابداری",
        
        # Update Inventory
        "update_inventory_name": "به‌روزرسانی موجودی",
        "update_inventory_desc": "به‌روزرسانی موجودی یک محصول",

        # AI Agent
        "ai_agent_name": "AI Agent",
        "ai_agent_desc": "عامل هوشمند برای تولید متن، تصمیم‌گیری و فراخوانی توابع",
    },
    "en": {
        # Create Notification
        "create_notification_name": "Create Notification",
        "create_notification_desc": "Create a notification for user",
        
        # Set Variable
        "set_variable_name": "Set Variable",
        "set_variable_desc": "Set a variable in context for use in subsequent nodes",
        
        # Log
        "log_name": "Log",
        "log_desc": "Record a log entry in workflow execution",
        
        # HTTP Request
        "http_request_name": "HTTP Request",
        "http_request_desc": "Send an HTTP request to specified URL",
        
        # Create Document
        "create_document_name": "Create Document",
        "create_document_desc": "Create an accounting document",
        
        # Update Inventory
        "update_inventory_name": "Update Inventory",
        "update_inventory_desc": "Update inventory of a product",

        # AI Agent
        "ai_agent_name": "AI Agent",
        "ai_agent_desc": "Intelligent agent for text generation, decision making and function calling",
    }
}


# ترجمه تریگر receipt_payment.created
RECEIPT_PAYMENT_CREATED_TRANSLATIONS = {
    "fa": {
        "trigger_name": "ایجاد دریافت/پرداخت",
        "trigger_description": "زمانی که یک سند دریافت یا پرداخت ثبت می‌شود",
        "field_enabled": "فعال",
        "field_enabled_desc": "غیرفعال کردن اجرای این تریگر بدون حذف از ورک‌فلو",
        "field_type": "نوع سند",
        "field_type_desc": "فقط دریافت یا فقط پرداخت",
        "receipt": "دریافت",
        "payment": "پرداخت",
        "field_min_amount": "حداقل مبلغ",
        "field_min_amount_desc": "فقط اگر مبلغ سند از این مقدار بیشتر یا مساوی باشد",
        "field_max_amount": "حداکثر مبلغ",
        "field_max_amount_desc": "فقط اگر مبلغ سند از این مقدار کمتر یا مساوی باشد",
        "field_payment_method_filter": "روش پرداخت",
        "field_payment_method_filter_desc": "حداقل یکی از روش‌های ثبت‌شده در سند باید در این لیست باشد",
        "cash": "نقد",
        "bank": "بانک",
        "check": "چک",
        "card": "کارت",
        "field_account_id_filter": "حساب معین اصلی",
        "field_account_id_filter_desc": "یکی از حساب‌های سطر سند باید این حساب باشد",
        "field_account_ids_filter": "هرکدام از حساب‌ها",
        "field_account_ids_filter_desc": "اگر هر سطر سند شامل یکی از این حساب‌های معین باشد، شرط برقرار است",
        "field_include_balance": "شامل موجودی",
        "field_include_balance_desc": "در صورت پشتیبانی، موجودی حساب به trigger_data اضافه می‌شود",
        "field_check_duplicate": "بررسی تکراری",
        "field_check_duplicate_desc": "منطق تشخیص تراکنش تکراری (در صورت پیاده‌سازی در بک‌اند)",
        "field_cooldown_seconds": "فاصلهٔ بین اجرا (ثانیه)",
        "field_cooldown_seconds_desc": "حداقل فاصلهٔ زمانی بین دو اجرای متوالی این ورک‌فلو",
        "field_person_id_filter": "شخص",
        "field_person_id_filter_desc": "فقط اگر این شخص در سطرهای سند باشد",
        "field_project_id_filter": "پروژه",
        "field_project_id_filter_desc": "فقط اسناد همین پروژه",
        "field_currency_id_filter": "ارز",
        "field_currency_id_filter_desc": "فقط اسناد با این ارز",
        "field_fiscal_year_id_filter": "سال مالی",
        "field_fiscal_year_id_filter_desc": "فقط اسناد این سال مالی",
        "field_description_contains": "کلمه در شرح",
        "field_description_contains_desc": "بخشی از شرح سند باید شامل این متن باشد",
    },
    "en": {
        "trigger_name": "Receipt / payment created",
        "trigger_description": "When a receipt or payment document is posted",
        "field_enabled": "Enabled",
        "field_enabled_desc": "Disable this trigger without removing the node",
        "field_type": "Document side",
        "field_type_desc": "Receipt only or payment only",
        "receipt": "Receipt",
        "payment": "Payment",
        "field_min_amount": "Minimum amount",
        "field_min_amount_desc": "Only when document amount is greater than or equal to this value",
        "field_max_amount": "Maximum amount",
        "field_max_amount_desc": "Only when document amount is less than or equal to this value",
        "field_payment_method_filter": "Payment methods",
        "field_payment_method_filter_desc": "At least one line method must match this list",
        "cash": "Cash",
        "bank": "Bank",
        "check": "Check",
        "card": "Card",
        "field_account_id_filter": "Ledger account",
        "field_account_id_filter_desc": "One of the document lines must use this account",
        "field_account_ids_filter": "Any of these accounts",
        "field_account_ids_filter_desc": "Triggers if any line hits one of these ledger accounts",
        "field_include_balance": "Include balance",
        "field_include_balance_desc": "When supported, append account balance to trigger data",
        "field_check_duplicate": "Duplicate check",
        "field_check_duplicate_desc": "Duplicate-transaction detection (if implemented)",
        "field_cooldown_seconds": "Cooldown (seconds)",
        "field_cooldown_seconds_desc": "Minimum delay between consecutive runs",
        "field_person_id_filter": "Person",
        "field_person_id_filter_desc": "Only when this person appears on a line",
        "field_project_id_filter": "Project",
        "field_project_id_filter_desc": "Only documents for this project",
        "field_currency_id_filter": "Currency",
        "field_currency_id_filter_desc": "Only documents in this currency",
        "field_fiscal_year_id_filter": "Fiscal year",
        "field_fiscal_year_id_filter_desc": "Only documents in this fiscal year",
        "field_description_contains": "Description contains",
        "field_description_contains_desc": "Document description must contain this text",
    },
}

RECEIPT_PAYMENT_UPDATED_TRANSLATIONS = copy.deepcopy(RECEIPT_PAYMENT_CREATED_TRANSLATIONS)
RECEIPT_PAYMENT_UPDATED_TRANSLATIONS["fa"]["trigger_name"] = "ویرایش دریافت/پرداخت"
RECEIPT_PAYMENT_UPDATED_TRANSLATIONS["fa"]["trigger_description"] = "زمانی که سند دریافت یا پرداخت ویرایش می‌شود"
RECEIPT_PAYMENT_UPDATED_TRANSLATIONS["en"]["trigger_name"] = "Receipt / payment updated"
RECEIPT_PAYMENT_UPDATED_TRANSLATIONS["en"]["trigger_description"] = "When a receipt or payment document is updated"

# ترجمه تریگر document.created
DOCUMENT_CREATED_TRANSLATIONS = {
    "fa": {
        "trigger_name": "ایجاد سند",
        "trigger_description": "زمانی که یک سند حسابداری (از جمله هزینه، درآمد، دستی و …) ثبت می‌شود",
        "field_enabled": "فعال",
        "field_enabled_desc": "غیرفعال کردن اجرای این تریگر",
        "field_document_type": "نوع سند",
        "field_document_type_desc": "محدود کردن به یک نوع سند مشخص",
        "expense": "هزینه",
        "income": "درآمد",
        "receipt": "دریافت",
        "payment": "پرداخت",
        "transfer": "انتقال",
        "manual": "دستی",
        "opening_balance": "تراز افتتاحیه",
        "year_end_closing": "سربندی سال",
        "field_min_amount": "حداقل مبلغ",
        "field_min_amount_desc": "بر اساس جمع بدهکار سند",
        "field_max_amount": "حداکثر مبلغ",
        "field_max_amount_desc": "بر اساس جمع بدهکار سند",
        "field_fiscal_year_filter": "سال مالی",
        "field_fiscal_year_filter_desc": "فقط اسناد این سال مالی",
        "field_user_id_filter": "کاربر ایجادکننده",
        "field_user_id_filter_desc": "فقط اگر سند توسط این کاربر ثبت شده باشد",
        "field_description_contains": "کلمه در شرح",
        "field_description_contains_desc": "بخشی از شرح باید شامل این متن باشد",
        "field_project_id_filter": "پروژه",
        "field_project_id_filter_desc": "فقط اسناد این پروژه",
        "field_currency_id_filter": "ارز",
        "field_currency_id_filter_desc": "فقط اسناد با این ارز",
        "field_person_id_filter": "شخص در سطرها",
        "field_person_id_filter_desc": "فقط اگر این شخص در یکی از سطرها باشد",
        "field_line_account_id_filter": "حساب در هر سطر",
        "field_line_account_id_filter_desc": "فقط اگر این حساب معین در هر سطر سند باشد",
        "field_item_account_id_filter": "حساب سطر اقلام",
        "field_item_account_id_filter_desc": "برای اسناد هزینه/درآمد: حساب اقلام باید شامل این حساب باشد",
        "field_cooldown_seconds": "فاصلهٔ بین اجرا (ثانیه)",
        "field_cooldown_seconds_desc": "حداقل فاصلهٔ زمانی بین دو اجرای متوالی",
    },
    "en": {
        "trigger_name": "Document created",
        "trigger_description": "When an accounting document is posted (expense, income, manual, etc.)",
        "field_enabled": "Enabled",
        "field_enabled_desc": "Disable this trigger",
        "field_document_type": "Document type",
        "field_document_type_desc": "Restrict to a specific document type",
        "expense": "Expense",
        "income": "Income",
        "receipt": "Receipt",
        "payment": "Payment",
        "transfer": "Transfer",
        "manual": "Manual",
        "opening_balance": "Opening balance",
        "year_end_closing": "Year-end closing",
        "field_min_amount": "Minimum amount",
        "field_min_amount_desc": "Based on total debit of the document",
        "field_max_amount": "Maximum amount",
        "field_max_amount_desc": "Based on total debit of the document",
        "field_fiscal_year_filter": "Fiscal year",
        "field_fiscal_year_filter_desc": "Only documents in this fiscal year",
        "field_user_id_filter": "Created by user",
        "field_user_id_filter_desc": "Only when posted by this user",
        "field_description_contains": "Description contains",
        "field_description_contains_desc": "Description must contain this text",
        "field_project_id_filter": "Project",
        "field_project_id_filter_desc": "Only documents for this project",
        "field_currency_id_filter": "Currency",
        "field_currency_id_filter_desc": "Only documents in this currency",
        "field_person_id_filter": "Person on lines",
        "field_person_id_filter_desc": "Only when this person appears on a line",
        "field_line_account_id_filter": "Account on any line",
        "field_line_account_id_filter_desc": "Only when this ledger account appears on a line",
        "field_item_account_id_filter": "Item line account",
        "field_item_account_id_filter_desc": "For expense/income: item lines must include this account",
        "field_cooldown_seconds": "Cooldown (seconds)",
        "field_cooldown_seconds_desc": "Minimum delay between consecutive runs",
    },
}

# ترجمه تریگر scheduled
SCHEDULED_TRIGGER_TRANSLATIONS = {
    "fa": {
        "trigger_name": "زمان‌بندی شده",
        "trigger_description": "اجرای ورک‌فلو در زمان مشخص (کرون دستی یا حالت ساده)",
        "field_schedule_mode": "نحوهٔ تنظیم زمان",
        "field_schedule_mode_desc": "کرون پیشرفته برای کاربران حرفه‌ای، یا حالت ساده بدون نوشتن کرون",
        "cron": "کرون پیشرفته (دستی)",
        "simple": "زمان‌بندی ساده",
        "field_schedule": "عبارت کرون",
        "field_schedule_desc": "پنج بخش: دقیقه ساعت روز ماه روزهفته — فقط در حالت کرون پیشرفته",
        "field_simple_repeat": "تکرار",
        "field_simple_repeat_desc": "نوع تکرار در حالت ساده (روزانه، هفتگی، هر چند دقیقه/ساعت)",
        "daily": "هر روز",
        "weekly": "هفتگی",
        "every_minutes": "هر چند دقیقه",
        "every_hours": "هر چند ساعت",
        "field_simple_time": "ساعت اجرا",
        "field_simple_time_desc": "فرمت HH:mm برای حالت روزانه یا هفتگی",
        "field_simple_weekday": "روز هفته (هفتگی)",
        "field_simple_weekday_desc": "۰=یکشنبه تا ۶=شنبه (مطابق استاندارد کرون)",
        "field_simple_interval": "فاصله (عدد)",
        "field_simple_interval_desc": "برای هر N دقیقه یا هر N ساعت",
        "field_timezone": "منطقهٔ زمانی",
        "field_timezone_desc": "زمان محلی برای محاسبهٔ اجرای کرون",
        "Asia_Tehran": "تهران",
        "UTC": "UTC",
        "Asia_Dubai": "دبی",
        "Europe_London": "لندن",
        "America_New_York": "نیویورک",
        "field_business_hours_only": "فقط ساعات کاری",
        "field_business_hours_only_desc": "بعد از تطبیق زمان، فقط در بازهٔ ساعت کاری اجرا شود",
        "field_business_hours_start": "شروع ساعت کاری",
        "field_business_hours_start_desc": "فرمت HH:mm",
        "field_business_hours_end": "پایان ساعت کاری",
        "field_business_hours_end_desc": "فرمت HH:mm",
        "field_exclude_holidays": "حذف تعطیلات",
        "field_exclude_holidays_desc": "رزرو برای نسخه‌های بعدی",
        "field_max_execution_time": "حداکثر زمان اجرا (ثانیه)",
        "field_max_execution_time_desc": "راهنمای UI؛ محدودیت سخت موتور جداگانه است",
        "field_retry_on_failure": "تلاش مجدد",
        "field_retry_on_failure_desc": "رزرو",
        "field_retry_attempts": "تعداد تلاش مجدد",
        "field_retry_attempts_desc": "رزرو",
    },
    "en": {
        "trigger_name": "Scheduled",
        "trigger_description": "Run the workflow on a schedule (advanced cron or simple mode)",
        "field_schedule_mode": "Schedule mode",
        "field_schedule_mode_desc": "Advanced cron for power users, or simple mode without writing cron",
        "cron": "Advanced cron",
        "simple": "Simple schedule",
        "field_schedule": "Cron expression",
        "field_schedule_desc": "Five fields: minute hour day month weekday — only in advanced mode",
        "field_simple_repeat": "Repeat",
        "field_simple_repeat_desc": "Repeat type in simple mode",
        "daily": "Daily",
        "weekly": "Weekly",
        "every_minutes": "Every N minutes",
        "every_hours": "Every N hours",
        "field_simple_time": "Time of day",
        "field_simple_time_desc": "HH:mm for daily or weekly",
        "field_simple_weekday": "Weekday (weekly)",
        "field_simple_weekday_desc": "0=Sunday … 6=Saturday (cron convention)",
        "field_simple_interval": "Interval (number)",
        "field_simple_interval_desc": "For every N minutes or every N hours",
        "field_timezone": "Timezone",
        "field_timezone_desc": "Local timezone used to evaluate the schedule",
        "Asia_Tehran": "Tehran",
        "UTC": "UTC",
        "Asia_Dubai": "Dubai",
        "Europe_London": "London",
        "America_New_York": "New York",
        "field_business_hours_only": "Business hours only",
        "field_business_hours_only_desc": "After schedule matches, only run within business hours",
        "field_business_hours_start": "Business hours start",
        "field_business_hours_start_desc": "HH:mm format",
        "field_business_hours_end": "Business hours end",
        "field_business_hours_end_desc": "HH:mm format",
        "field_exclude_holidays": "Exclude holidays",
        "field_exclude_holidays_desc": "Reserved for future use",
        "field_max_execution_time": "Max execution time (seconds)",
        "field_max_execution_time_desc": "UI hint; engine limits may differ",
        "field_retry_on_failure": "Retry on failure",
        "field_retry_on_failure_desc": "Reserved",
        "field_retry_attempts": "Retry attempts",
        "field_retry_attempts_desc": "Reserved",
    },
}

# ترجمه تریگر document.updated (فیلدها همان document.created)
DOCUMENT_UPDATED_TRANSLATIONS = copy.deepcopy(DOCUMENT_CREATED_TRANSLATIONS)
DOCUMENT_UPDATED_TRANSLATIONS["fa"]["trigger_name"] = "ویرایش سند"
DOCUMENT_UPDATED_TRANSLATIONS["fa"]["trigger_description"] = "هنگام ویرایش سند حسابداری (مثلاً سند دستی)"
DOCUMENT_UPDATED_TRANSLATIONS["en"]["trigger_name"] = "Document updated"
DOCUMENT_UPDATED_TRANSLATIONS["en"]["trigger_description"] = "When an accounting document is updated"


# ترجمه اکشن business_backup
BUSINESS_BACKUP_TRANSLATIONS = {
    "fa": {
        "action_name": "پشتیبان کسب‌وکار",
        "action_description": "ایجاد فایل پشتیبان کامل و ذخیره در فایل‌سرور؛ خروجی file_id برای نود بعدی (مثلاً ارسال فایل در بله با $node_id.file_id). اختیاری: FTP",
        "field_upload_to_ftp": "ارسال به FTP",
        "field_upload_to_ftp_desc": "پس از ذخیرهٔ فایل، کپی روی سرور FTP (نیازمند تنظیمات FTP کسب‌وکار)",
    },
    "en": {
        "action_name": "Business backup",
        "action_description": "Create a full .hbx backup and store it; exposes file_id for the next node (e.g. Bale: $node_id.file_id). Optional FTP",
        "field_upload_to_ftp": "Upload to FTP",
        "field_upload_to_ftp_desc": "After saving, upload a copy to FTP (requires FTP settings)",
    },
}

CRM_WEB_CHAT_SEND_MESSAGE_TRANSLATIONS = {
    "fa": {
        "action_name": "ارسال پیام در چت وب CRM",
        "action_description": "ارسال پاسخ عامل در همان مکالمه چت وب (ویجت). پیش‌فرض بدون تریگر «پاسخ عامل» برای جلوگیری از حلقه اتوماسیون.",
        "field_conversation_id": "شناسه مکالمه",
        "field_conversation_id_desc": "معمولاً از نود تریگر: $id_nod_trigger.conversation_id",
        "field_body": "متن پیام",
        "field_body_desc": "متن قابل حل با $node.field؛ برای پیام فقط فایل می‌تواند خالی باشد",
        "field_file_storage_id": "شناسه فایل پیوست",
        "field_file_storage_id_desc": "اختیاری؛ همان شناسه file_storage در سیستم",
        "field_agent_user_id": "کاربر عامل",
        "field_agent_user_id_desc": "خالی = مالک کسب‌وکار یا کاربر اجراکننده ورک‌فلو",
        "field_fire_message_sent_workflow_trigger": "شلیک تریگر پاسخ عامل",
        "field_fire_message_sent_workflow_trigger_desc": "اگر روشن باشد، ورک‌فلوهایی با تریگر «پاسخ عامل» هم اجرا می‌شوند (احتمال حلقه)",
        "field_mark_as_workflow_automation": "علامت اتوماسیون ورک‌فلو",
        "field_mark_as_workflow_automation_desc": "در payload تریگر، automation_source=workflow برای فیلتر در تریگر",
    },
    "en": {
        "action_name": "Send CRM web chat message",
        "action_description": "Post an agent reply in the same web chat conversation (widget). Default: do not fire the agent-reply workflow trigger to avoid automation loops.",
        "field_conversation_id": "Conversation ID",
        "field_conversation_id_desc": "Usually from trigger node: $trigger_node.conversation_id",
        "field_body": "Message body",
        "field_body_desc": "Resolvable text; may be empty if only sending file_storage_id",
        "field_file_storage_id": "Attachment file ID",
        "field_file_storage_id_desc": "Optional file_storage id",
        "field_agent_user_id": "Agent user",
        "field_agent_user_id_desc": "Empty = business owner or workflow runner",
        "field_fire_message_sent_workflow_trigger": "Fire agent-reply trigger",
        "field_fire_message_sent_workflow_trigger_desc": "If true, workflows on agent message sent may run (loop risk)",
        "field_mark_as_workflow_automation": "Mark as workflow automation",
        "field_mark_as_workflow_automation_desc": "When firing trigger, set automation_source=workflow for filtering",
    },
}

TRIGGER_TRANSLATIONS_BY_KEY: Dict[str, Any] = {
    "receipt_payment.created": RECEIPT_PAYMENT_CREATED_TRANSLATIONS,
    "receipt_payment.updated": RECEIPT_PAYMENT_UPDATED_TRANSLATIONS,
    "document.created": DOCUMENT_CREATED_TRANSLATIONS,
    "document.updated": DOCUMENT_UPDATED_TRANSLATIONS,
    "scheduled": SCHEDULED_TRIGGER_TRANSLATIONS,
    "person.created": PERSON_WORKFLOW_TRIGGER_TRANSLATIONS,
    "person.updated": PERSON_WORKFLOW_TRIGGER_UPDATED_TRANSLATIONS,
    "invoice.created": INVOICE_WORKFLOW_TRIGGER_TRANSLATIONS,
    "invoice.sales.created": INVOICE_WORKFLOW_TRIGGER_TRANSLATIONS,
    "invoice.purchase.created": INVOICE_WORKFLOW_TRIGGER_TRANSLATIONS,
    "invoice.updated": INVOICE_WORKFLOW_TRIGGER_UPDATED_TRANSLATIONS,
    "invoice.sales.updated": INVOICE_WORKFLOW_TRIGGER_UPDATED_TRANSLATIONS,
    "invoice.purchase.updated": INVOICE_WORKFLOW_TRIGGER_UPDATED_TRANSLATIONS,
    "crm.chat.conversation.started": CRM_CHAT_CONVERSATION_STARTED_TRANSLATIONS,
    "crm.chat.message.received": CRM_CHAT_MESSAGE_RECEIVED_TRANSLATIONS,
    "crm.chat.message.sent": CRM_CHAT_MESSAGE_SENT_TRANSLATIONS,
    "crm.chat.conversation.assigned": CRM_CHAT_CONVERSATION_ASSIGNED_TRANSLATIONS,
    "crm.chat.conversation.resolved": CRM_CHAT_CONVERSATION_RESOLVED_TRANSLATIONS,
    "crm.chat.conversation.reopened": CRM_CHAT_CONVERSATION_REOPENED_TRANSLATIONS,
}


def get_translation(key: str, lang: str = "fa", context: str = None) -> str:
    """
    دریافت ترجمه یک کلید
    
    Args:
        key: کلید ترجمه (مثل: "action_name")
        lang: زبان (fa/en)
        context: context ترجمه (مثل: "create_invoice", "send_telegram")
    
    Returns:
        رشته ترجمه شده یا خود key اگر یافت نشد
    """
    lang = lang.lower()
    if lang not in ["fa", "en"]:
        lang = "fa"
    
    # جستجو در ترجمه‌های خاص
    if context:
        if context in WORKFLOW_ACTION_TRANSLATIONS:
            wmap = WORKFLOW_ACTION_TRANSLATIONS[context]
            if lang in wmap and key in wmap[lang]:
                return wmap[lang][key]

        if context in TRIGGER_TRANSLATIONS_BY_KEY:
            trans = TRIGGER_TRANSLATIONS_BY_KEY[context]
            if lang in trans and key in trans[lang]:
                return trans[lang][key]

        translations_map = {
            "create_invoice": CREATE_INVOICE_TRANSLATIONS,
            "send_telegram": SEND_TELEGRAM_TRANSLATIONS,
            "send_bale": SEND_BALE_TRANSLATIONS,
            "send_email": SEND_EMAIL_TRANSLATIONS,
            "ai_agent": AI_AGENT_TRANSLATIONS,
            "business_backup": BUSINESS_BACKUP_TRANSLATIONS,
            "crm_web_chat_send_message": CRM_WEB_CHAT_SEND_MESSAGE_TRANSLATIONS,
            "others": OTHER_ACTIONS_TRANSLATIONS,
        }
        
        trans = translations_map.get(context, {})
        if lang in trans and key in trans[lang]:
            return trans[lang][key]
    
    # جستجو در ترجمه‌های مشترک
    if lang in COMMON_TRANSLATIONS and key in COMMON_TRANSLATIONS[lang]:
        return COMMON_TRANSLATIONS[lang][key]
    
    # اگر یافت نشد، خود key را برگردان
    return key


def translate_metadata(metadata: Dict[str, Any], lang: str = "fa", action_key: str = None) -> Dict[str, Any]:
    """
    ترجمه metadata یک action
    
    Args:
        metadata: metadata اصلی
        lang: زبان مورد نظر
        action_key: کلید action (مثل: create_invoice)
    
    Returns:
        metadata ترجمه شده
    """
    translated = metadata.copy()
    
    # ترجمه name و description
    if action_key:
        translated["name"] = get_translation("action_name", lang, action_key)
        translated["description"] = get_translation("action_description", lang, action_key)
    
    # ترجمه config_schema
    if "config_schema" in translated:
        schema = translated["config_schema"]
        translated_schema = {}
        
        for field_key, field_config in schema.items():
            if isinstance(field_config, dict):
                translated_field = field_config.copy()
                
                # ترجمه description
                desc_key = f"field_{field_key}_desc"
                translated_field["description"] = get_translation(desc_key, lang, action_key)

                # ترجمه برچسب فیلد (title)
                label_key = f"field_{field_key}"
                label = get_translation(label_key, lang, action_key)
                if label != label_key:
                    translated_field["title"] = label

                # ترجمه enum values
                if "enum" in translated_field:
                    translated_enum_labels = {}
                    for enum_value in translated_field["enum"]:
                        label_key = enum_value.replace("-", "_").replace(".", "_")
                        translated_enum_labels[enum_value] = get_translation(label_key, lang, action_key)
                    
                    if "ui_config" not in translated_field:
                        translated_field["ui_config"] = {}
                    translated_field["ui_config"]["labels"] = translated_enum_labels
                
                # ترجمه placeholder
                placeholder_key = f"field_{field_key}_placeholder"
                placeholder = get_translation(placeholder_key, lang, action_key)
                if placeholder != placeholder_key:  # اگر ترجمه پیدا شد
                    if "ui_config" not in translated_field:
                        translated_field["ui_config"] = {}
                    translated_field["ui_config"]["placeholder"] = placeholder
                
                translated_schema[field_key] = translated_field
        
        translated["config_schema"] = translated_schema
    
    # ترجمه ui_config groups
    if "ui_config" in translated and "groups" in translated["ui_config"]:
        for group in translated["ui_config"]["groups"]:
            group_key = group.get("key", "").lower().replace(" ", "_").replace("‌", "_")
            group_trans_key = f"group_{group_key}"
            group["label"] = get_translation(group_trans_key, lang, action_key)
    
    # ترجمه help_texts
    if "ui_config" in translated and "help_texts" in translated["ui_config"]:
        help_texts = translated["ui_config"]["help_texts"]
        translated_help = {}
        for field_key, _ in help_texts.items():
            help_key = f"field_{field_key}_help"
            translated_help[field_key] = get_translation(help_key, lang, action_key)
        translated["ui_config"]["help_texts"] = translated_help
    
    return translated


def translate_trigger_metadata(metadata: Dict[str, Any], lang: str = "fa", trigger_key: str = None) -> Dict[str, Any]:
    """
    ترجمه metadata یک trigger (نام، توضیح، فیلدهای config_schema).
    """
    if not trigger_key or trigger_key not in TRIGGER_TRANSLATIONS_BY_KEY:
        return metadata.copy()

    translated = metadata.copy()
    translated["name"] = get_translation("trigger_name", lang, trigger_key)
    translated["description"] = get_translation("trigger_description", lang, trigger_key)

    if "config_schema" not in translated:
        return translated

    schema = translated["config_schema"]
    translated_schema: Dict[str, Any] = {}

    for field_key, field_config in schema.items():
        if isinstance(field_config, dict):
            translated_field = field_config.copy()
            desc_key = f"field_{field_key}_desc"
            translated_field["description"] = get_translation(desc_key, lang, trigger_key)
            label_key = f"field_{field_key}"
            label = get_translation(label_key, lang, trigger_key)
            if label != label_key:
                translated_field["title"] = label

            if "enum" in translated_field:
                translated_enum_labels = {}
                for enum_value in translated_field["enum"]:
                    ek = (
                        str(enum_value)
                        .replace("-", "_")
                        .replace(".", "_")
                        .replace("/", "_")
                    )
                    lbl = get_translation(ek, lang, trigger_key)
                    if lbl == ek:
                        lbl = get_translation(str(enum_value), lang, trigger_key)
                    translated_enum_labels[enum_value] = lbl
                if "ui_config" not in translated_field:
                    translated_field["ui_config"] = {}
                translated_field["ui_config"]["labels"] = translated_enum_labels

            if translated_field.get("type") == "array" and isinstance(translated_field.get("items"), dict):
                items = translated_field["items"]
                if isinstance(items, dict) and items.get("enum"):
                    translated_item_labels = {}
                    for enum_value in items["enum"]:
                        ek = (
                            str(enum_value)
                            .replace("-", "_")
                            .replace(".", "_")
                            .replace("/", "_")
                        )
                        il = get_translation(ek, lang, trigger_key)
                        if il == ek:
                            il = get_translation(str(enum_value), lang, trigger_key)
                        translated_item_labels[enum_value] = il
                    uc = dict(translated_field.get("ui_config") or {})
                    uc["labels"] = translated_item_labels
                    translated_field["ui_config"] = uc

            placeholder_key = f"field_{field_key}_placeholder"
            placeholder = get_translation(placeholder_key, lang, trigger_key)
            if placeholder != placeholder_key:
                if "ui_config" not in translated_field:
                    translated_field["ui_config"] = {}
                translated_field["ui_config"]["placeholder"] = placeholder

            translated_schema[field_key] = translated_field
        else:
            translated_schema[field_key] = field_config

    translated["config_schema"] = translated_schema
    return translated


def get_all_translation_keys(action_key: str = None) -> Dict[str, list]:
    """
    استخراج تمام کلیدهای ترجمه برای یک action
    
    Returns:
        {
            "fa": [...],
            "en": [...]
        }
    """
    if action_key == "create_invoice":
        trans = CREATE_INVOICE_TRANSLATIONS
    elif action_key == "send_telegram":
        trans = SEND_TELEGRAM_TRANSLATIONS
    elif action_key == "send_bale":
        trans = SEND_BALE_TRANSLATIONS
    elif action_key == "send_email":
        trans = SEND_EMAIL_TRANSLATIONS
    elif action_key == "ai_agent":
        trans = AI_AGENT_TRANSLATIONS
    else:
        trans = COMMON_TRANSLATIONS
    
    return {
        "fa": list(trans.get("fa", {}).keys()),
        "en": list(trans.get("en", {}).keys())
    }


