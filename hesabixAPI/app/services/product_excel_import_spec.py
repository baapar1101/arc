"""
تعریف ستون‌های ایمپورت اکسل کالا/خدمت.

قالب کاربر فقط ستون‌های قابل‌فهم (نام، کد، مسیر دسته، …) را دارد.
شناسه‌های داخلی هنوز در ایمپورت پذیرفته می‌شوند تا فایل‌های قدیمی نشکنند.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, Iterable, List, Sequence


def normalize_header(value: object) -> str:
    s = "" if value is None else str(value)
    s = s.replace("\u200c", " ")
    s = " ".join(s.split()).strip().lower()
    return s


@dataclass(frozen=True)
class ImportColumn:
    key: str
    labels: Dict[str, str]
    help_fa: str
    help_en: str
    required: bool = False
    in_user_template: bool = True
    aliases: Sequence[str] = field(default_factory=tuple)
    group: str = "basic"


USER_TEMPLATE_COLUMNS: List[ImportColumn] = [
    ImportColumn(
        "code",
        {"fa": "کد", "en": "Code"},
        "اختیاری. اگر خالی باشد سیستم کد یکتا می‌سازد.",
        "Optional. Leave empty to auto-generate a unique code.",
        aliases=("product code", "کد کالا"),
        group="basic",
    ),
    ImportColumn(
        "name",
        {"fa": "نام", "en": "Name"},
        "الزامی. عنوان کالا یا خدمت همان‌طور که در برنامه دیده می‌شود.",
        "Required. Product or service title as shown in the app.",
        required=True,
        aliases=("title", "عنوان", "نام کالا"),
        group="basic",
    ),
    ImportColumn(
        "item_type",
        {"fa": "نوع", "en": "Type"},
        "کالا یا خدمت. خالی = کالا (فقط هنگام ایجاد).",
        "product or service. Empty = product (create only).",
        aliases=("item type", "نوع کالا"),
        group="basic",
    ),
    ImportColumn(
        "is_active",
        {"fa": "فعال", "en": "Active"},
        "بله / خیر. سلول خالی در به‌روزرسانی تغییری نمی‌دهد.",
        "Yes / No. Empty cell does not change the value on update.",
        aliases=("is active", "وضعیت", "active"),
        group="basic",
    ),
    ImportColumn(
        "description",
        {"fa": "توضیحات", "en": "Description"},
        "توضیح متنی کالا یا خدمت.",
        "Free-text description.",
        group="basic",
    ),
    ImportColumn(
        "general_barcodes",
        {"fa": "بارکدهای عمومی", "en": "Barcodes"},
        "چند بارکد را با ویرگول جدا کنید.",
        "Comma-separated public barcodes.",
        aliases=("barcode", "بارکد", "general barcodes"),
        group="basic",
    ),
    ImportColumn(
        "category_path",
        {"fa": "مسیر دسته‌بندی", "en": "Category Path"},
        "مسیر کامل مثل «مواد اولیه > پلاستیک». شناسه لازم نیست. از شیت دسته‌بندی‌ها کپی کنید.",
        "Full path like \"Raw materials > Plastics\". No ID needed. Copy from the Categories sheet.",
        aliases=("category path", "مسیر دسته بندی", "دسته", "دسته‌بندی", "دسته بندی"),
        group="category",
    ),
    ImportColumn(
        "main_unit",
        {"fa": "واحد اصلی", "en": "Main Unit"},
        "مثلاً عدد، کیلوگرم، متر.",
        "e.g. pcs, kg, meter.",
        aliases=("main unit", "واحد"),
        group="units",
    ),
    ImportColumn(
        "secondary_unit",
        {"fa": "واحد فرعی", "en": "Secondary Unit"},
        "اختیاری. اگر پر شود ضریب تبدیل هم لازم است.",
        "Optional. Conversion factor is required when set.",
        aliases=("secondary unit",),
        group="units",
    ),
    ImportColumn(
        "unit_conversion_factor",
        {"fa": "ضریب تبدیل", "en": "Unit Conversion Factor"},
        "چند واحد اصلی در یک واحد فرعی. مثال: ۱۲.",
        "How many main units in one secondary unit. Example: 12.",
        aliases=("unit conversion factor", "conversion factor"),
        group="units",
    ),
    ImportColumn(
        "base_sales_price",
        {"fa": "قیمت فروش", "en": "Sales Price"},
        "قیمت فروش پایه به ارز اصلی کسب‌وکار.",
        "Base sales price in the business base currency.",
        aliases=("sales price", "قیمت"),
        group="pricing",
    ),
    ImportColumn(
        "base_purchase_price",
        {"fa": "قیمت خرید", "en": "Purchase Price"},
        "قیمت خرید پایه به ارز اصلی کسب‌وکار.",
        "Base purchase price in the business base currency.",
        aliases=("purchase price",),
        group="pricing",
    ),
    ImportColumn(
        "base_sales_note",
        {"fa": "یادداشت فروش", "en": "Sales Note"},
        "یادداشت پیش‌فرض روی ردیف فروش.",
        "Default note on sales lines.",
        aliases=("sales note",),
        group="pricing",
    ),
    ImportColumn(
        "base_purchase_note",
        {"fa": "یادداشت خرید", "en": "Purchase Note"},
        "یادداشت پیش‌فرض روی ردیف خرید.",
        "Default note on purchase lines.",
        aliases=("purchase note",),
        group="pricing",
    ),
    ImportColumn(
        "sales_price_fx",
        {"fa": "قیمت فروش ارزی", "en": "FX Sales Price"},
        "فقط برای کسب‌وکار چندارزی.",
        "Multi-currency businesses only.",
        aliases=("fx sales price", "sales price fx"),
        group="fx",
    ),
    ImportColumn(
        "purchase_price_fx",
        {"fa": "قیمت خرید ارزی", "en": "FX Purchase Price"},
        "فقط برای کسب‌وکار چندارزی.",
        "Multi-currency businesses only.",
        aliases=("fx purchase price", "purchase price fx"),
        group="fx",
    ),
    ImportColumn(
        "price_fx_currency_code",
        {"fa": "کد ارز قیمت", "en": "Price Currency Code"},
        "مثل USD یا EUR. از شیت ارزها کپی کنید. شناسه ارز لازم نیست.",
        "e.g. USD or EUR. Copy from the Currencies sheet. No currency ID needed.",
        aliases=("price currency", "currency code", "کد ارز"),
        group="fx",
    ),
    ImportColumn(
        "auto_update_base_from_fx",
        {"fa": "به‌روزرسانی قیمت پایه از ارز", "en": "Auto Update Base From FX"},
        "بله / خیر. قیمت پایه از نرخ × قیمت ارزی به‌روز شود.",
        "Yes / No. Update base price from rate × FX price.",
        aliases=("auto update base from fx",),
        group="fx",
    ),
    ImportColumn(
        "track_inventory",
        {"fa": "کنترل موجودی", "en": "Track Inventory"},
        "بله / خیر. برای خدمت نادیده گرفته می‌شود. سلول خالی در به‌روزرسانی تغییری نمی‌دهد.",
        "Yes / No. Ignored for services. Empty cell does not change the value on update.",
        aliases=("track inventory",),
        group="inventory",
    ),
    ImportColumn(
        "inventory_mode",
        {"fa": "حالت موجودی", "en": "Inventory Mode"},
        "فله‌ای یا یونیک.",
        "bulk or unique.",
        aliases=("inventory mode", "mode"),
        group="inventory",
    ),
    ImportColumn(
        "track_serial",
        {"fa": "ردیابی سریال", "en": "Track Serial"},
        "بله / خیر. فقط برای کالای یونیک.",
        "Yes / No. Unique inventory only.",
        aliases=("track serial",),
        group="inventory",
    ),
    ImportColumn(
        "track_barcode",
        {"fa": "ردیابی بارکد یونیک", "en": "Track Unique Barcode"},
        "بله / خیر. فقط برای کالای یونیک.",
        "Yes / No. Unique inventory only.",
        aliases=("track barcode",),
        group="inventory",
    ),
    ImportColumn(
        "warehouse_code",
        {"fa": "کد انبار", "en": "Warehouse Code"},
        "کد انبار پیش‌فرض. از شیت انبارها کپی کنید.",
        "Default warehouse code. Copy from the Warehouses sheet.",
        aliases=("warehouse code",),
        group="inventory",
    ),
    ImportColumn(
        "warehouse_name",
        {"fa": "نام انبار", "en": "Warehouse Name"},
        "اگر کد انبار خالی باشد با نام پیدا می‌شود.",
        "Used when warehouse code is empty.",
        aliases=("warehouse name", "انبار"),
        group="inventory",
    ),
    ImportColumn(
        "opening_balance_quantity",
        {"fa": "تعداد اولیه", "en": "Opening Balance Qty"},
        "فقط کالا با کنترل موجودی. در سند تراز افتتاحیه ثبت می‌شود.",
        "Tracked products only. Stored on the opening-balance document.",
        aliases=("opening balance qty", "opening balance quantity", "موجودی اولیه"),
        group="inventory",
    ),
    ImportColumn(
        "opening_balance_cost_price",
        {"fa": "بهای تمام‌شده (هر واحد)", "en": "Opening Balance Cost"},
        "بهای تمام‌شده هر واحد برای تعداد اولیه.",
        "Unit cost for opening quantity.",
        aliases=(
            "opening balance cost",
            "بهای تمام شده (هر واحد)",
            "قیمت تمام شده",
        ),
        group="inventory",
    ),
    ImportColumn(
        "reorder_point",
        {"fa": "نقطه سفارش مجدد", "en": "Reorder Point"},
        "حداقل موجودی برای هشدار سفارش.",
        "Minimum stock for reorder alerts.",
        aliases=("reorder point",),
        group="inventory",
    ),
    ImportColumn(
        "min_order_qty",
        {"fa": "حداقل مقدار سفارش", "en": "Min Order Qty"},
        "حداقل تعداد در سفارش خرید.",
        "Minimum purchase order quantity.",
        aliases=("min order qty", "minimum order qty"),
        group="inventory",
    ),
    ImportColumn(
        "lead_time_days",
        {"fa": "زمان تامین (روز)", "en": "Lead Time (Days)"},
        "زمان تأمین به روز.",
        "Lead time in days.",
        aliases=("lead time (days)", "زمان تأمین (روز)", "lead time"),
        group="inventory",
    ),
    ImportColumn(
        "is_sales_taxable",
        {"fa": "مشمول مالیات فروش", "en": "Sales Taxable"},
        "بله / خیر. سلول خالی در به‌روزرسانی تغییری نمی‌دهد.",
        "Yes / No. Empty cell does not change the value on update.",
        aliases=("sales taxable",),
        group="tax",
    ),
    ImportColumn(
        "is_purchase_taxable",
        {"fa": "مشمول مالیات خرید", "en": "Purchase Taxable"},
        "بله / خیر. سلول خالی در به‌روزرسانی تغییری نمی‌دهد.",
        "Yes / No. Empty cell does not change the value on update.",
        aliases=("purchase taxable",),
        group="tax",
    ),
    ImportColumn(
        "sales_tax_rate",
        {"fa": "نرخ مالیات فروش (%)", "en": "Sales Tax Rate (%)"},
        "درصد، مثلاً ۹.",
        "Percent, e.g. 9.",
        aliases=("sales tax rate (%)", "sales tax rate"),
        group="tax",
    ),
    ImportColumn(
        "purchase_tax_rate",
        {"fa": "نرخ مالیات خرید (%)", "en": "Purchase Tax Rate (%)"},
        "درصد، مثلاً ۹.",
        "Percent, e.g. 9.",
        aliases=("purchase tax rate (%)", "purchase tax rate"),
        group="tax",
    ),
    ImportColumn(
        "tax_type_code",
        {"fa": "کد نوع مالیات", "en": "Tax Type Code"},
        "از شیت انواع مالیات کپی کنید. شناسه لازم نیست.",
        "Copy from the Tax Types sheet. No ID needed.",
        aliases=("tax type code",),
        group="tax",
    ),
    ImportColumn(
        "tax_type_title",
        {"fa": "عنوان نوع مالیات", "en": "Tax Type Title"},
        "اگر کد خالی باشد با عنوان پیدا می‌شود.",
        "Used when tax type code is empty.",
        aliases=("tax type title", "نوع مالیات"),
        group="tax",
    ),
    ImportColumn(
        "tax_code",
        {"fa": "کد مالیاتی", "en": "Tax Code"},
        "کد مالیاتی کالا در سامانه مؤدیان.",
        "Product tax code for tax reporting.",
        aliases=("tax code",),
        group="tax",
    ),
    ImportColumn(
        "tax_unit_code",
        {"fa": "کد واحد مالیاتی", "en": "Tax Unit Code"},
        "از شیت واحدهای مالیاتی کپی کنید.",
        "Copy from the Tax Units sheet.",
        aliases=("tax unit code",),
        group="tax",
    ),
    ImportColumn(
        "tax_unit_name",
        {"fa": "نام واحد مالیاتی", "en": "Tax Unit Name"},
        "اگر کد خالی باشد با نام پیدا می‌شود.",
        "Used when tax unit code is empty.",
        aliases=("tax unit name", "واحد مالیاتی"),
        group="tax",
    ),
    ImportColumn(
        "attribute_titles",
        {"fa": "نام ویژگی‌ها", "en": "Attribute Titles"},
        "چند عنوان را با ویرگول جدا کنید. از شیت ویژگی‌ها کپی کنید.",
        "Comma-separated titles. Copy from the Attributes sheet.",
        aliases=("attribute titles", "نام ویژگی ها", "ویژگی‌ها", "ویژگی ها"),
        group="attributes",
    ),
    ImportColumn(
        "catalog_brand",
        {"fa": "برند", "en": "Brand"},
        "برند برای کاتالوگ عمومی.",
        "Brand for the public catalog.",
        aliases=("brand",),
        group="catalog",
    ),
    ImportColumn(
        "catalog_model",
        {"fa": "مدل", "en": "Model"},
        "مدل کالا.",
        "Product model.",
        aliases=("model",),
        group="catalog",
    ),
    ImportColumn(
        "catalog_country_of_origin",
        {"fa": "کشور سازنده", "en": "Country of Origin"},
        "کشور مبدأ.",
        "Country of origin.",
        aliases=("country of origin", "کشور مبدأ"),
        group="catalog",
    ),
    ImportColumn(
        "catalog_short_description",
        {"fa": "خلاصه کاتالوگ", "en": "Catalog Summary"},
        "خلاصه کوتاه برای نمایش عمومی.",
        "Short public catalog summary.",
        aliases=("catalog summary", "catalog short description"),
        group="catalog",
    ),
    ImportColumn(
        "is_public_catalog",
        {"fa": "انتشار در کاتالوگ عمومی", "en": "Public Catalog"},
        "بله / خیر.",
        "Yes / No.",
        aliases=("public catalog", "is public catalog"),
        group="catalog",
    ),
]

# شناسه‌های داخلی — در قالب کاربر نیستند، فقط برای سازگاری فایل قدیمی.
LEGACY_ID_COLUMNS: List[ImportColumn] = [
    ImportColumn(
        "category_id",
        {"fa": "شناسه دسته‌بندی", "en": "Category ID"},
        "فقط برای فایل‌های قدیمی. به‌جای آن مسیر دسته‌بندی را پر کنید.",
        "Legacy only. Prefer Category Path.",
        in_user_template=False,
        aliases=("category id", "شناسه دسته بندی"),
        group="legacy",
    ),
    ImportColumn(
        "category",
        {"fa": "دسته‌بندی", "en": "Category"},
        "نام یا مسیر دسته. معادل مسیر دسته‌بندی.",
        "Category name or path. Same as Category Path.",
        in_user_template=False,
        aliases=("category name",),
        group="legacy",
    ),
    ImportColumn(
        "default_warehouse_id",
        {"fa": "شناسه انبار پیش‌فرض", "en": "Default Warehouse ID"},
        "فقط برای فایل‌های قدیمی. کد یا نام انبار را پر کنید.",
        "Legacy only. Prefer warehouse code or name.",
        in_user_template=False,
        aliases=("default warehouse id", "شناسه انبار پیش فرض"),
        group="legacy",
    ),
    ImportColumn(
        "tax_type_id",
        {"fa": "شناسه نوع مالیات", "en": "Tax Type ID"},
        "فقط برای فایل‌های قدیمی.",
        "Legacy only.",
        in_user_template=False,
        aliases=("tax type id",),
        group="legacy",
    ),
    ImportColumn(
        "tax_unit_id",
        {"fa": "شناسه واحد مالیاتی", "en": "Tax Unit ID"},
        "فقط برای فایل‌های قدیمی.",
        "Legacy only.",
        in_user_template=False,
        aliases=("tax unit id",),
        group="legacy",
    ),
    ImportColumn(
        "attribute_ids",
        {"fa": "شناسه ویژگی‌ها", "en": "Attribute IDs"},
        "فقط برای فایل‌های قدیمی. نام ویژگی‌ها را پر کنید.",
        "Legacy only. Prefer attribute titles.",
        in_user_template=False,
        aliases=("attribute ids", "شناسه ویژگی ها"),
        group="legacy",
    ),
    ImportColumn(
        "price_fx_currency_id",
        {"fa": "شناسه ارز قیمت", "en": "Price Currency ID"},
        "فقط برای فایل‌های قدیمی. کد ارز را پر کنید.",
        "Legacy only. Prefer currency code.",
        in_user_template=False,
        aliases=("price currency id", "fx currency id"),
        group="legacy",
    ),
]

ALL_COLUMNS: List[ImportColumn] = [*USER_TEMPLATE_COLUMNS, *LEGACY_ID_COLUMNS]
ALL_COLUMN_KEYS = frozenset(c.key for c in ALL_COLUMNS)

EXCEL_ONLY_RESOLVE_KEYS = frozenset({
    "category_path",
    "category",
    "attribute_titles",
    "tax_type_code",
    "tax_type_title",
    "tax_unit_code",
    "tax_unit_name",
    "warehouse_code",
    "warehouse_name",
    "opening_balance_quantity",
    "opening_balance_cost_price",
    "price_fx_currency_code",
})

HELPER_KEYS = frozenset({
    "_row",
    "_provided_keys",
    "_created_attribute_titles",
    "_would_create_attribute_titles",
    "_sample_row",
})

BOOLEAN_KEYS = frozenset({
    "track_inventory",
    "is_sales_taxable",
    "is_purchase_taxable",
    "is_active",
    "track_serial",
    "track_barcode",
    "auto_update_base_from_fx",
    "is_public_catalog",
})

DECIMAL_KEYS = frozenset({
    "base_sales_price",
    "base_purchase_price",
    "sales_tax_rate",
    "purchase_tax_rate",
    "unit_conversion_factor",
    "opening_balance_quantity",
    "opening_balance_cost_price",
    "sales_price_fx",
    "purchase_price_fx",
})

INT_KEYS = frozenset({
    "reorder_point",
    "min_order_qty",
    "lead_time_days",
    "category_id",
    "tax_type_id",
    "tax_unit_id",
    "default_warehouse_id",
    "price_fx_currency_id",
})

CREATE_UPDATE_SCHEMA_KEYS = frozenset({
    "code",
    "name",
    "item_type",
    "description",
    "general_barcodes",
    "barcode",
    "is_active",
    "category_id",
    "main_unit",
    "secondary_unit",
    "unit_conversion_factor",
    "base_sales_price",
    "base_purchase_price",
    "base_sales_note",
    "base_purchase_note",
    "sales_price_fx",
    "purchase_price_fx",
    "price_fx_currency_id",
    "auto_update_base_from_fx",
    "track_inventory",
    "inventory_mode",
    "track_serial",
    "track_barcode",
    "default_warehouse_id",
    "reorder_point",
    "min_order_qty",
    "lead_time_days",
    "is_sales_taxable",
    "is_purchase_taxable",
    "sales_tax_rate",
    "purchase_tax_rate",
    "tax_type_id",
    "tax_code",
    "tax_unit_id",
    "attribute_ids",
    "catalog_brand",
    "catalog_model",
    "catalog_country_of_origin",
    "catalog_short_description",
    "is_public_catalog",
    "opening_balance",
})

HEADER_GROUP_COLORS = {
    "basic": "1F4E79",
    "category": "0D7377",
    "units": "5D6D7E",
    "pricing": "1E8449",
    "fx": "117A65",
    "inventory": "B9770E",
    "tax": "6C3483",
    "attributes": "1A5276",
    "catalog": "7D3C98",
}

SAMPLE_PRODUCT_CODE = "P1001"
SAMPLE_PRODUCT_NAMES = frozenset({"نمونه کالا", "sample product"})

DATA_SHEET_NAMES = frozenset({
    normalize_header(n)
    for n in (
        "template",
        "products",
        "کالاها",
        "کالا و خدمت",
        "کالاها و خدمات",
    )
})

LOOKUP_SHEET_NAMES = frozenset({
    normalize_header(n)
    for n in (
        "راهنما",
        "instructions",
        "دسته‌بندی‌ها",
        "دسته بندی ها",
        "categories",
        "انبارها",
        "warehouses",
        "انواع مالیات",
        "tax types",
        "واحدهای مالیاتی",
        "tax units",
        "ویژگی‌ها",
        "ویژگی ها",
        "attributes",
        "ارزها",
        "currencies",
    )
})

MAX_PRODUCT_IMPORT_FILE_BYTES = 15 * 1024 * 1024
MAX_PRODUCT_IMPORT_DATA_ROWS = 5000


def iter_accepted_columns() -> Iterable[ImportColumn]:
    return ALL_COLUMNS


def build_header_aliases() -> Dict[str, str]:
    aliases: Dict[str, str] = {}
    # ستون‌های قالب کاربر بعد از ستون‌های قدیمی اعمال می‌شوند تا برچسب مشترک
    # مثل «دسته‌بندی» به مسیر دسته (نه شناسه) نگاشت شود.
    for col in [*LEGACY_ID_COLUMNS, *USER_TEMPLATE_COLUMNS]:
        aliases[normalize_header(col.key)] = col.key
        for label in col.labels.values():
            aliases[normalize_header(label)] = col.key
        for extra in col.aliases:
            aliases[normalize_header(extra)] = col.key
    return aliases


HEADER_ALIASES = build_header_aliases()


def localized_header(col: ImportColumn, locale: str) -> str:
    return col.labels.get(locale) or col.labels.get("en") or col.key


def localized_help(col: ImportColumn, locale: str) -> str:
    return col.help_fa if locale == "fa" else col.help_en
