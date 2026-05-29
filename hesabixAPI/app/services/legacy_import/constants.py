from __future__ import annotations

# Default Hesabix cloud; users may override for self-hosted legacy installs.
DEFAULT_LEGACY_SERVER_URL = "https://app.hesabix.ir"

LEGACY_ARCHIVE_CREATE_PATH = "/api/backup/archive/create"
LEGACY_BUSINESS_INFO_PATH = "/api/business/get/info/{bid}"
LEGACY_BUSINESS_LIST_PATH = "/api/business/list"
LEGACY_PERSON_TYPES_PATH = "/api/person/types/get"

# Hesabix v1 person_type.id → Persian label (fallback if API types unavailable)
DEFAULT_LEGACY_PERSON_TYPE_ID_MAP: dict[int, str] = {
    1: "مشتری",
    2: "بازاریاب",
    3: "کارمند",
    4: "تامین‌کننده",
    5: "همکار",
    6: "فروشنده",
    7: "سهامدار",
}

# hesabdari_doc.type → new document / service routing
LEGACY_DOC_TYPE_TO_INVOICE: dict[str, str] = {
    "sell": "invoice_sales",
    "buy": "invoice_purchase",
    "rfsell": "invoice_sales_return",
    "rfbuy": "invoice_purchase_return",
}

LEGACY_DOC_TYPE_TO_RECEIPT_PAYMENT: dict[str, str] = {
    "person_receive": "receipt",
    "sell_receive": "receipt",
    "person_send": "payment",
    "buy_send": "payment",
}

LEGACY_DOC_TYPE_TO_EXPENSE_INCOME: dict[str, str] = {
    "cost": "expense",
    "income": "income",
}

# انواعی که عمداً رد می‌شوند (پیام اختصاصی)
LEGACY_DOC_TYPE_SKIP_MESSAGES: dict[str, str] = {
    "open_balance": "مانده افتتاحیه — در نسخه جدید از مسیر دیگری تنظیم می‌شود",
}

# Archive JSON file names inside ZIP
ARCHIVE_MANIFEST = "manifest.json"
ARCHIVE_DATA_PREFIX = "data/"

ARCHIVE_TABLES = (
    "business.json",
    "years.json",
    "money_used.json",
    "persons.json",
    "commodity_cats.json",
    "commodity_units.json",
    "commodities.json",
    "bank_accounts.json",
    "storerooms.json",
    "storeroom_transfer_types.json",
    "storeroom_tickets.json",
    "storeroom_items.json",
    "hesabdari_docs.json",
    "hesabdari_rows.json",
    "hesabdari_tables.json",
)

IMPORT_MODE_LEGACY_API = "legacy_api"

# HTTP client limits (production safety)
LEGACY_HTTP_TIMEOUT_SEC = 120.0
LEGACY_HTTP_MAX_ARCHIVE_BYTES = 250 * 1024 * 1024  # 250 MB
LEGACY_HTTP_CONNECT_TIMEOUT_SEC = 15.0
