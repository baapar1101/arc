"""
سیستم ترجمه برای نودهای ورک‌فلو
این ماژول رشته‌های قابل ترجمه برای metadata نودها را مدیریت می‌کند
"""
from typing import Dict, Any
from enum import Enum


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


# ترجمه‌های اکشن "ارسال تلگرام"
SEND_TELEGRAM_TRANSLATIONS = {
    "fa": {
        "action_name": "ارسال پیام تلگرام",
        "action_description": "ارسال پیام به کاربر عضو کسب و کار از طریق تلگرام (فقط کاربران متصل به ربات)",
        
        "field_user_id": "کاربر دریافت‌کننده",
        "field_user_id_desc": "شناسه کاربر عضو کسب و کار که به ربات تلگرام متصل است (می‌تواند از نودهای قبلی باشد: $node_id.user_id)",
        
        "field_message": "متن پیام",
        "field_message_desc": "متن پیام",
        "field_message_placeholder": "متن پیام خود را وارد کنید...",
        
        "field_parse_mode": "حالت پارس",
        "field_parse_mode_desc": "حالت پارس (HTML/Markdown/None)",
        
        "field_disable_web_page_preview": "غیرفعال کردن پیش‌نمایش لینک",
        "field_disable_web_page_preview_desc": "غیرفعال کردن پیش‌نمایش لینک",
        
        "field_retry_on_failure": "تلاش مجدد در صورت خطا",
        "field_retry_on_failure_desc": "تلاش مجدد در صورت خطا",
        
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
        "field_message_desc": "Message text",
        "field_message_placeholder": "Enter your message...",
        
        "field_parse_mode": "Parse Mode",
        "field_parse_mode_desc": "Parse mode (HTML/Markdown/None)",
        
        "field_disable_web_page_preview": "Disable Web Page Preview",
        "field_disable_web_page_preview_desc": "Disable web page preview",
        
        "field_retry_on_failure": "Retry on Failure",
        "field_retry_on_failure_desc": "Retry on failure",
        
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
    }
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
        translations_map = {
            "create_invoice": CREATE_INVOICE_TRANSLATIONS,
            "send_telegram": SEND_TELEGRAM_TRANSLATIONS,
            "send_email": SEND_EMAIL_TRANSLATIONS,
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
    elif action_key == "send_email":
        trans = SEND_EMAIL_TRANSLATIONS
    else:
        trans = COMMON_TRANSLATIONS
    
    return {
        "fa": list(trans.get("fa", {}).keys()),
        "en": list(trans.get("en", {}).keys())
    }


