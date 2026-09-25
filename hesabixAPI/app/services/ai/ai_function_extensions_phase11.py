"""
ثبت functionهای فاز ۱۱ AI — تکمیل پوشش ابزارها روی دامنه‌های باقی‌مانده API
(به جز بخش‌های admin و support).

شامل:
  - حسابداری: لیست/جزئیات/ایجاد/ویرایش/حذف حساب (کدینگ)، تنظیمات شماره‌گذاری اسناد
  - انبار/کالا: مکان‌های انبار، استقرار کالا، گزارش‌های تخصصی انبار،
    ویژگی‌های کالا (CRUD)، جستجوی کالای یونیک (سریال/بارکد)
  - مالی: نرخ ارز کسب‌وکار، تسهیلات دریافتی، کیف پول، درگاه‌های پرداخت
  - عملیات ویرایش/حذف اسناد: چک، انتقال، دریافت/پرداخت، هزینه/درآمد
  - متفرقه: اعلان‌ها، اطلاع‌رسانی‌ها، شرح‌های پرتکرار، کاربران کسب‌وکار

الگوی امنیتی همانند سایر فازها:
  - handlerهای خواندنی کسب‌وکار از registry._create_handler استفاده می‌کنند
    (تزریق business_id از session + بررسی دسترسی).
  - handlerهای نوشتنی به‌صورت مستقیم (args, context) نوشته شده‌اند و
    business_id را از session می‌گیرند؛ همگی requires_approval=True دارند.
  - ابزارهای سطح کاربر (اعلان‌ها/اطلاع‌رسانی) business_context_required=False.
"""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Optional, TYPE_CHECKING

from app.services.ai.function_registry import AIRole, AIFunction

if TYPE_CHECKING:
    from app.services.ai.function_registry import AIFunctionRegistry

from app.services.ai.ai_tool_query_params import (
    COMMON_LIST_QUERY_PROPERTIES as _COMMON_LIST_PROPS,
)

_ALL_ROLES = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
_WRITE_ROLES = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.ADMIN}


def _effective_business_id(args: Dict[str, Any], context: Dict[str, Any]) -> int:
    """شناسه کسب‌وکار مؤثر از session/context (امنیت: ورودی AI نادیده گرفته می‌شود)."""
    bid = (
        context.get("session_business_id")
        or context.get("business_id")
        or args.get("business_id")
    )
    if not bid:
        raise ValueError("business context الزامی است")
    return int(bid)


def _user_display_name(user: Any) -> Optional[str]:
    """ساخت نام نمایشی کاربر از first_name/last_name با fallback به موبایل/ایمیل."""
    if user is None:
        return None
    parts = [
        getattr(user, "first_name", None),
        getattr(user, "last_name", None),
    ]
    name = " ".join(p for p in parts if p).strip()
    return name or getattr(user, "mobile", None) or getattr(user, "email", None)


def _parse_dt(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    txt = str(value).strip()
    for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(txt, fmt)
        except ValueError:
            continue
    return None


def register_phase11_business_functions(registry: "AIFunctionRegistry") -> None:
    create_handler = registry._create_handler  # noqa: SLF001

    # ============================================================
    # حسابداری — کدینگ حساب‌ها
    # ============================================================
    registry.register(
        AIFunction(
            name="list_accounts",
            description=(
                "لیست حساب‌های کدینگ (حساب‌های عمومی + اختصاصی کسب‌وکار) به‌همراه "
                "code, name, account_type, parent_id. برای ساخت درخت از parent_id استفاده کن."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "search": {"type": "string", "description": "جستجو در کد یا نام (اختیاری)"},
                    "account_type": {"type": "string", "description": "فیلتر نوع حساب (اختیاری)"},
                    "parent_id": {"type": "integer", "description": "فیلتر والد (اختیاری)"},
                },
                "required": [],
            },
            handler=create_handler(_list_accounts),
            allowed_roles=_ALL_ROLES,
            required_permissions=["chart_of_accounts.view"],
            category="accounting",
        )
    )

    registry.register(
        AIFunction(
            name="get_account",
            description="دریافت جزئیات یک حساب کدینگ بر اساس شناسه.",
            parameters_schema={
                "type": "object",
                "properties": {"account_id": {"type": "integer", "description": "شناسه حساب"}},
                "required": ["account_id"],
            },
            handler=create_handler(_get_account),
            allowed_roles=_ALL_ROLES,
            required_permissions=["chart_of_accounts.view"],
            category="accounting",
        )
    )

    registry.register(
        AIFunction(
            name="create_account",
            description="ایجاد یک حساب کدینگ جدید برای کسب‌وکار. شناسه کسب‌وکار خودکار است.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "name": {"type": "string", "description": "نام حساب"},
                    "code": {"type": "string", "description": "کد حساب (یکتا)"},
                    "account_type": {"type": "string", "description": "نوع حساب (مثل asset, liability, income, expense)"},
                    "parent_id": {"type": "integer", "description": "شناسه حساب والد (اختیاری)"},
                },
                "required": ["name", "code", "account_type"],
            },
            handler=_create_account_handler,
            allowed_roles=_WRITE_ROLES,
            required_permissions=["chart_of_accounts.add"],
            category="accounting",
            requires_approval=True,
            risk_level="medium",
            is_readonly=False,
        )
    )

    registry.register(
        AIFunction(
            name="update_account",
            description="ویرایش یک حساب کدینگ اختصاصی کسب‌وکار. حساب‌های عمومی قابل ویرایش نیستند.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "account_id": {"type": "integer", "description": "شناسه حساب"},
                    "name": {"type": "string", "description": "نام جدید (اختیاری)"},
                    "code": {"type": "string", "description": "کد جدید (اختیاری)"},
                    "account_type": {"type": "string", "description": "نوع جدید (اختیاری)"},
                    "parent_id": {"type": "integer", "description": "والد جدید (اختیاری)"},
                },
                "required": ["account_id"],
            },
            handler=_update_account_handler,
            allowed_roles=_WRITE_ROLES,
            required_permissions=["chart_of_accounts.edit"],
            category="accounting",
            requires_approval=True,
            risk_level="medium",
            is_readonly=False,
        )
    )

    registry.register(
        AIFunction(
            name="delete_account",
            description="حذف یک حساب کدینگ اختصاصی. اگر فرزند یا سند داشته باشد حذف نمی‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {"account_id": {"type": "integer", "description": "شناسه حساب"}},
                "required": ["account_id"],
            },
            handler=_delete_account_handler,
            allowed_roles=_WRITE_ROLES,
            required_permissions=["chart_of_accounts.delete"],
            category="accounting",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )

    registry.register(
        AIFunction(
            name="get_document_numbering_settings",
            description="دریافت تنظیمات شماره‌گذاری اسناد کسب‌وکار (پیشوند، تقویم، فرمت، شمارهٔ شروع).",
            parameters_schema={
                "type": "object",
                "properties": {
                    "document_type": {"type": "string", "description": "فیلتر نوع سند (اختیاری)"},
                },
                "required": [],
            },
            handler=create_handler(_doc_numbering_settings),
            allowed_roles=_ALL_ROLES,
            required_permissions=["settings.view"],
            category="accounting",
        )
    )

    # ============================================================
    # انبار / کالا
    # ============================================================
    registry.register(
        AIFunction(
            name="list_warehouse_locations",
            description="درخت و لیست مکان‌های (قفسه/طبقه) یک انبار. warehouse_id الزامی است.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "warehouse_id": {"type": "integer", "description": "شناسه انبار"},
                },
                "required": ["warehouse_id"],
            },
            handler=create_handler(_list_wh_locations),
            allowed_roles=_ALL_ROLES,
            required_permissions=["warehouses.view"],
            category="warehouse",
        )
    )

    registry.register(
        AIFunction(
            name="list_warehouse_placements",
            description="لیست استقرار کالاها در مکان‌های یک انبار (کدام کالا در کدام قفسه با چه مقدار).",
            parameters_schema={
                "type": "object",
                "properties": {
                    "warehouse_id": {"type": "integer", "description": "شناسه انبار"},
                    "product_id": {"type": "integer", "description": "فیلتر کالا (اختیاری)"},
                    "location_id": {"type": "integer", "description": "فیلتر مکان (اختیاری)"},
                },
                "required": ["warehouse_id"],
            },
            handler=create_handler(_list_wh_placements),
            allowed_roles=_ALL_ROLES,
            required_permissions=["warehouses.view"],
            category="warehouse",
        )
    )

    registry.register(
        AIFunction(
            name="get_warehouse_report",
            description=(
                "گزارش‌های تخصصی انبار. report_type یکی از: "
                "documents_summary (خلاصه حواله‌ها)، slow_moving (کالای کم‌گردش)، "
                "critical_stock (موجودی بحرانی)، inter_warehouse_transfers (انتقال بین‌انباری)، "
                "adjustments (اصلاح موجودی)، performance (عملکرد انبار)، "
                "product_movement (گردش یک کالا — product_id لازم)، valuation (ارزش‌گذاری موجودی)، "
                "pending (اسناد معلق)، turnover (نرخ گردش موجودی)."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "report_type": {
                        "type": "string",
                        "enum": [
                            "documents_summary",
                            "slow_moving",
                            "critical_stock",
                            "inter_warehouse_transfers",
                            "adjustments",
                            "performance",
                            "product_movement",
                            "valuation",
                            "pending",
                            "turnover",
                        ],
                        "description": "نوع گزارش",
                    },
                    "product_id": {"type": "integer", "description": "برای product_movement لازم است"},
                    "from_date": {"type": "string", "format": "date", "description": "تاریخ شروع (اختیاری)"},
                    "to_date": {"type": "string", "format": "date", "description": "تاریخ پایان (اختیاری)"},
                    "as_of_date": {"type": "string", "format": "date", "description": "تاریخ مبنا (اختیاری)"},
                    "warehouse_ids": {"type": "array", "items": {"type": "integer"}, "description": "فیلتر انبارها (اختیاری)"},
                    "category_ids": {"type": "array", "items": {"type": "integer"}, "description": "فیلتر دسته‌ها (اختیاری)"},
                    "days_without_movement": {"type": "integer", "description": "آستانه روز برای slow_moving (پیش‌فرض 90)"},
                    "skip": {"type": "integer"},
                    "take": {"type": "integer"},
                },
                "required": ["report_type"],
            },
            handler=create_handler(_warehouse_report),
            allowed_roles=_ALL_ROLES,
            required_permissions=["reports.view"],
            category="warehouse",
        )
    )

    registry.register(
        AIFunction(
            name="list_product_attributes",
            description="لیست ویژگی‌های تعریف‌شده کالا (مثل رنگ، سایز) با نوع داده و گزینه‌ها.",
            parameters_schema={
                "type": "object",
                "properties": dict(_COMMON_LIST_PROPS),
                "required": [],
            },
            handler=create_handler(_list_product_attributes),
            allowed_roles=_ALL_ROLES,
            required_permissions=["product_attributes.view", "products.view"],
            category="products",
        )
    )

    registry.register(
        AIFunction(
            name="get_product_attribute",
            description="جزئیات یک ویژگی کالا.",
            parameters_schema={
                "type": "object",
                "properties": {"attribute_id": {"type": "integer", "description": "شناسه ویژگی"}},
                "required": ["attribute_id"],
            },
            handler=create_handler(_get_product_attribute),
            allowed_roles=_ALL_ROLES,
            required_permissions=["product_attributes.view", "products.view"],
            category="products",
        )
    )

    registry.register(
        AIFunction(
            name="create_product_attribute",
            description="ایجاد یک ویژگی کالای جدید (text/number/date/select/boolean).",
            parameters_schema={
                "type": "object",
                "properties": {
                    "title": {"type": "string", "description": "عنوان ویژگی"},
                    "description": {"type": "string", "description": "توضیحات (اختیاری)"},
                    "data_type": {
                        "type": "string",
                        "enum": ["text", "number", "date", "select", "boolean"],
                        "description": "نوع داده (پیش‌فرض text)",
                    },
                    "options": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "گزینه‌ها (فقط برای نوع select)",
                    },
                },
                "required": ["title"],
            },
            handler=_create_product_attribute_handler,
            allowed_roles=_WRITE_ROLES,
            required_permissions=["product_attributes.add", "products.write"],
            category="products",
            requires_approval=True,
            risk_level="medium",
            is_readonly=False,
        )
    )

    registry.register(
        AIFunction(
            name="update_product_attribute",
            description="ویرایش یک ویژگی کالا.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "attribute_id": {"type": "integer", "description": "شناسه ویژگی"},
                    "title": {"type": "string", "description": "عنوان جدید (اختیاری)"},
                    "description": {"type": "string", "description": "توضیحات جدید (اختیاری)"},
                    "data_type": {
                        "type": "string",
                        "enum": ["text", "number", "date", "select", "boolean"],
                        "description": "نوع جدید (اختیاری)",
                    },
                    "options": {"type": "array", "items": {"type": "string"}, "description": "گزینه‌های جدید (اختیاری)"},
                },
                "required": ["attribute_id"],
            },
            handler=_update_product_attribute_handler,
            allowed_roles=_WRITE_ROLES,
            required_permissions=["product_attributes.edit", "products.write"],
            category="products",
            requires_approval=True,
            risk_level="medium",
            is_readonly=False,
        )
    )

    registry.register(
        AIFunction(
            name="delete_product_attribute",
            description="حذف یک ویژگی کالا.",
            parameters_schema={
                "type": "object",
                "properties": {"attribute_id": {"type": "integer", "description": "شناسه ویژگی"}},
                "required": ["attribute_id"],
            },
            handler=_delete_product_attribute_handler,
            allowed_roles=_WRITE_ROLES,
            required_permissions=["product_attributes.delete", "products.write"],
            category="products",
            requires_approval=True,
            risk_level="medium",
            is_readonly=False,
        )
    )

    registry.register(
        AIFunction(
            name="search_product_instances",
            description=(
                "جستجوی کالاهای یونیک (سریال‌دار) بر اساس کالا، انبار، وضعیت، سریال یا بارکد. "
                "status: available/sold/warranty/defective."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "product_id": {"type": "integer", "description": "فیلتر کالا (اختیاری)"},
                    "warehouse_id": {"type": "integer", "description": "فیلتر انبار (اختیاری)"},
                    "status": {
                        "type": "string",
                        "enum": ["available", "sold", "warranty", "defective"],
                        "description": "فیلتر وضعیت (اختیاری)",
                    },
                    "serial_number": {"type": "string", "description": "جستجوی سریال (اختیاری)"},
                    "barcode": {"type": "string", "description": "جستجوی بارکد (اختیاری)"},
                    "skip": {"type": "integer"},
                    "take": {"type": "integer"},
                },
                "required": [],
            },
            handler=create_handler(_search_product_instances),
            allowed_roles=_ALL_ROLES,
            required_permissions=["inventory.read"],
            category="products",
        )
    )

    # ============================================================
    # مالی
    # ============================================================
    registry.register(
        AIFunction(
            name="list_currency_rates",
            description="لیست نرخ‌های ارز ثبت‌شدهٔ کسب‌وکار (نسبت به ارز پایه).",
            parameters_schema={
                "type": "object",
                "properties": {
                    "currency_id": {"type": "integer", "description": "فیلتر ارز (اختیاری)"},
                    "skip": {"type": "integer"},
                    "take": {"type": "integer"},
                },
                "required": [],
            },
            handler=create_handler(_list_currency_rates),
            allowed_roles=_ALL_ROLES,
            required_permissions=["currency_revaluation.view"],
            category="financial",
        )
    )

    registry.register(
        AIFunction(
            name="resolve_currency_rate",
            description="یافتن نرخ مؤثر یک ارز نسبت به ارز پایه در یک تاریخ مشخص.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "currency_id": {"type": "integer", "description": "شناسه ارز"},
                    "as_of_date": {"type": "string", "format": "date", "description": "تاریخ مبنا (اختیاری، پیش‌فرض امروز)"},
                },
                "required": ["currency_id"],
            },
            handler=create_handler(_resolve_currency_rate),
            allowed_roles=_ALL_ROLES,
            required_permissions=["currency_revaluation.view"],
            category="financial",
        )
    )

    registry.register(
        AIFunction(
            name="list_loan_facilities",
            description="لیست تسهیلات دریافتی (وام‌ها) کسب‌وکار با مبلغ، نرخ و وضعیت.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "search": {"type": "string", "description": "جستجو در عنوان (اختیاری)"},
                    "skip": {"type": "integer"},
                    "take": {"type": "integer"},
                },
                "required": [],
            },
            handler=create_handler(_list_loan_facilities),
            allowed_roles=_ALL_ROLES,
            required_permissions=["loan_facilities.view"],
            category="financial",
        )
    )

    registry.register(
        AIFunction(
            name="get_loan_facility",
            description="جزئیات یک تسهیل دریافتی به‌همراه اقساط (در صورت درخواست).",
            parameters_schema={
                "type": "object",
                "properties": {
                    "facility_id": {"type": "integer", "description": "شناسه تسهیل"},
                    "with_installments": {"type": "boolean", "description": "نمایش اقساط (اختیاری)"},
                },
                "required": ["facility_id"],
            },
            handler=create_handler(_get_loan_facility),
            allowed_roles=_ALL_ROLES,
            required_permissions=["loan_facilities.view"],
            category="financial",
        )
    )

    registry.register(
        AIFunction(
            name="get_wallet_overview",
            description="خلاصهٔ کیف پول کسب‌وکار: موجودی قابل‌برداشت، در انتظار و ارز پایه.",
            parameters_schema={"type": "object", "properties": {}, "required": []},
            handler=create_handler(_wallet_overview),
            allowed_roles=_ALL_ROLES,
            required_permissions=["wallet.view"],
            category="financial",
        )
    )

    registry.register(
        AIFunction(
            name="list_wallet_transactions",
            description="لیست تراکنش‌های کیف پول کسب‌وکار.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "from_date": {"type": "string", "format": "date", "description": "از تاریخ (اختیاری)"},
                    "to_date": {"type": "string", "format": "date", "description": "تا تاریخ (اختیاری)"},
                    "skip": {"type": "integer"},
                    "take": {"type": "integer", "description": "تعداد (پیش‌فرض 50)"},
                },
                "required": [],
            },
            handler=create_handler(_wallet_transactions),
            allowed_roles=_ALL_ROLES,
            required_permissions=["wallet.view"],
            category="financial",
        )
    )

    registry.register(
        AIFunction(
            name="get_wallet_metrics",
            description="آمار کیف پول در یک بازه: مجموع ورودی/خروجی، کارمزدها و خالص.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "from_date": {"type": "string", "format": "date", "description": "از تاریخ (اختیاری)"},
                    "to_date": {"type": "string", "format": "date", "description": "تا تاریخ (اختیاری)"},
                },
                "required": [],
            },
            handler=create_handler(_wallet_metrics),
            allowed_roles=_ALL_ROLES,
            required_permissions=["wallet.view"],
            category="financial",
        )
    )

    registry.register(
        AIFunction(
            name="list_payment_gateways",
            description="لیست درگاه‌های پرداخت فعال در دسترس کسب‌وکار.",
            parameters_schema={"type": "object", "properties": {}, "required": []},
            handler=create_handler(_list_payment_gateways),
            allowed_roles=_ALL_ROLES,
            required_permissions=["settings.view"],
            category="financial",
        )
    )

    # ============================================================
    # عملیات ویرایش/حذف اسناد
    # ============================================================
    registry.register(
        AIFunction(
            name="update_check",
            description="ویرایش یک چک (ویرایش جزئی؛ فقط فیلدهای ارسالی تغییر می‌کنند).",
            parameters_schema={
                "type": "object",
                "properties": {
                    "check_id": {"type": "integer", "description": "شناسه چک"},
                    "type": {"type": "string", "enum": ["received", "transferred"], "description": "نوع چک (اختیاری)"},
                    "person_id": {"type": "integer", "description": "شناسه شخص (اختیاری)"},
                    "amount": {"type": "number", "description": "مبلغ (اختیاری)"},
                    "currency_id": {"type": "integer", "description": "شناسه ارز (اختیاری)"},
                    "check_number": {"type": "string", "description": "شماره چک (اختیاری)"},
                    "sayad_code": {"type": "string", "description": "کد صیاد (اختیاری)"},
                    "bank_name": {"type": "string", "description": "نام بانک (اختیاری)"},
                    "branch_name": {"type": "string", "description": "نام شعبه (اختیاری)"},
                    "issue_date": {"type": "string", "format": "date", "description": "تاریخ صدور (اختیاری)"},
                    "due_date": {"type": "string", "format": "date", "description": "تاریخ سررسید (اختیاری)"},
                },
                "required": ["check_id"],
            },
            handler=_update_check_handler,
            allowed_roles=_WRITE_ROLES,
            required_permissions=["checks.write"],
            category="checks",
            requires_approval=True,
            risk_level="medium",
            is_readonly=False,
        )
    )

    registry.register(
        AIFunction(
            name="delete_check",
            description="حذف یک چک پرداختنی یا دریافتنی با شناسه. عملیات مخرب است و برگشت‌پذیر نیست.",
            parameters_schema={
                "type": "object",
                "properties": {"check_id": {"type": "integer", "description": "شناسه چک"}},
                "required": ["check_id"],
            },
            handler=_delete_check_handler,
            allowed_roles=_WRITE_ROLES,
            required_permissions=["checks.write"],
            category="checks",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )

    registry.register(
        AIFunction(
            name="update_transfer",
            description=(
                "ویرایش سند انتقال وجه بین حساب‌ها (جایگزینی کامل؛ مبدأ و مقصد را کامل بده)."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "document_id": {"type": "integer", "description": "شناسه سند انتقال"},
                    "document_date": {"type": "string", "format": "date", "description": "تاریخ سند"},
                    "currency_id": {"type": "integer", "description": "شناسه ارز"},
                    "amount": {"type": "number", "description": "مبلغ انتقال"},
                    "commission": {"type": "number", "description": "کارمزد (اختیاری)"},
                    "from_account_type": {"type": "string", "enum": ["bank", "cash_register", "petty_cash"], "description": "نوع حساب مبدأ"},
                    "from_account_id": {"type": "integer", "description": "شناسه حساب مبدأ"},
                    "to_account_type": {"type": "string", "enum": ["bank", "cash_register", "petty_cash"], "description": "نوع حساب مقصد"},
                    "to_account_id": {"type": "integer", "description": "شناسه حساب مقصد"},
                    "description": {"type": "string", "description": "توضیحات (اختیاری)"},
                },
                "required": [
                    "document_id",
                    "document_date",
                    "currency_id",
                    "amount",
                    "from_account_type",
                    "from_account_id",
                    "to_account_type",
                    "to_account_id",
                ],
            },
            handler=_update_transfer_handler,
            allowed_roles=_WRITE_ROLES,
            required_permissions=["transfers.write"],
            category="financial",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )

    registry.register(
        AIFunction(
            name="delete_transfer",
            description="حذف یک سند انتقال وجه.",
            parameters_schema={
                "type": "object",
                "properties": {"document_id": {"type": "integer", "description": "شناسه سند انتقال"}},
                "required": ["document_id"],
            },
            handler=_delete_transfer_handler,
            allowed_roles=_WRITE_ROLES,
            required_permissions=["transfers.write"],
            category="financial",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )

    from app.services.ai.ai_tool_payloads import (
        UPDATE_EXPENSE_INCOME_DESCRIPTION,
        UPDATE_EXPENSE_INCOME_PARAMETERS_SCHEMA,
        UPDATE_RECEIPT_PAYMENT_DESCRIPTION,
        UPDATE_RECEIPT_PAYMENT_PARAMETERS_SCHEMA,
    )

    registry.register(
        AIFunction(
            name="update_receipt_payment",
            description=UPDATE_RECEIPT_PAYMENT_DESCRIPTION,
            parameters_schema=UPDATE_RECEIPT_PAYMENT_PARAMETERS_SCHEMA,
            handler=_update_receipt_payment_handler,
            allowed_roles=_WRITE_ROLES,
            required_permissions=["receipts_payments.write"],
            category="financial",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )

    registry.register(
        AIFunction(
            name="delete_receipt_payment",
            description="حذف یک سند دریافت/پرداخت.",
            parameters_schema={
                "type": "object",
                "properties": {"document_id": {"type": "integer", "description": "شناسه سند"}},
                "required": ["document_id"],
            },
            handler=_delete_receipt_payment_handler,
            allowed_roles=_WRITE_ROLES,
            required_permissions=["receipts_payments.write"],
            category="financial",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )

    registry.register(
        AIFunction(
            name="update_expense_income",
            description=UPDATE_EXPENSE_INCOME_DESCRIPTION,
            parameters_schema=UPDATE_EXPENSE_INCOME_PARAMETERS_SCHEMA,
            handler=_update_expense_income_handler,
            allowed_roles=_WRITE_ROLES,
            required_permissions=["expenses_income.write"],
            category="financial",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )

    registry.register(
        AIFunction(
            name="delete_expense_income",
            description="حذف یک سند هزینه/درآمد.",
            parameters_schema={
                "type": "object",
                "properties": {"document_id": {"type": "integer", "description": "شناسه سند"}},
                "required": ["document_id"],
            },
            handler=_delete_expense_income_handler,
            allowed_roles=_WRITE_ROLES,
            required_permissions=["expenses_income.write"],
            category="financial",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )

    # ============================================================
    # متفرقه
    # ============================================================
    registry.register(
        AIFunction(
            name="list_frequent_descriptions",
            description="لیست شرح‌های پرتکرار تعریف‌شدهٔ کسب‌وکار (برای اسناد/فاکتورها).",
            parameters_schema={
                "type": "object",
                "properties": {
                    "scope": {"type": "string", "description": "حوزهٔ شرح (اختیاری)"},
                },
                "required": [],
            },
            handler=create_handler(_list_frequent_descriptions),
            allowed_roles=_ALL_ROLES,
            required_permissions=["invoices.read"],
            category="business",
        )
    )

    registry.register(
        AIFunction(
            name="list_business_users",
            description="لیست کاربران/اعضای کسب‌وکار (مالک و اعضا) با نقش و وضعیت — فقط خواندنی.",
            parameters_schema={"type": "object", "properties": {}, "required": []},
            handler=_list_business_users_handler,
            allowed_roles={AIRole.BUSINESS_OWNER, AIRole.ADMIN},
            required_permissions=["settings.view"],
            category="business",
        )
    )

    registry.register(
        AIFunction(
            name="list_business_notification_templates",
            description="لیست قالب‌های اطلاع‌رسانی تعریف‌شدهٔ کسب‌وکار.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "channel": {"type": "string", "description": "فیلتر کانال (اختیاری)"},
                    "status": {"type": "string", "description": "فیلتر وضعیت (اختیاری)"},
                    "search": {"type": "string", "description": "جستجو (اختیاری)"},
                    "skip": {"type": "integer"},
                    "take": {"type": "integer"},
                },
                "required": [],
            },
            handler=_list_notification_templates_handler,
            allowed_roles=_ALL_ROLES,
            required_permissions=["settings.view"],
            category="business",
        )
    )

    registry.register(
        AIFunction(
            name="list_business_notification_logs",
            description="لیست لاگ ارسال اطلاع‌رسانی‌های کسب‌وکار (وضعیت تحویل پیام‌ها).",
            parameters_schema={
                "type": "object",
                "properties": {
                    "channel": {"type": "string", "description": "فیلتر کانال (اختیاری)"},
                    "status": {"type": "string", "description": "فیلتر وضعیت (اختیاری)"},
                    "skip": {"type": "integer"},
                    "take": {"type": "integer"},
                },
                "required": [],
            },
            handler=_list_notification_logs_handler,
            allowed_roles=_ALL_ROLES,
            required_permissions=["settings.view"],
            category="business",
        )
    )

    # --- سطح کاربر (بدون نیاز به business context) ---
    registry.register(
        AIFunction(
            name="list_my_businesses",
            description=(
                "لیست کسب‌وکارهای کاربر جاری (مالک + عضو) با نقش و شناسه. "
                "برای انتخاب/تغییر context کسب‌وکار مفید است."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "search": {"type": "string", "description": "جستجو در نام (اختیاری)"},
                    "limit": {"type": "integer", "description": "تعداد (پیش‌فرض 20)"},
                },
                "required": [],
            },
            handler=_list_my_businesses_handler,
            allowed_roles=_ALL_ROLES,
            business_context_required=False,
            required_permissions=[],
            category="user",
        )
    )

    registry.register(
        AIFunction(
            name="list_announcements",
            description="لیست اعلان‌های سامانه برای کاربر جاری.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "only_unread": {"type": "boolean", "description": "فقط خوانده‌نشده‌ها (اختیاری)"},
                    "level": {"type": "string", "description": "سطح اعلان (اختیاری)"},
                    "page": {"type": "integer", "description": "شماره صفحه (پیش‌فرض 1)"},
                    "limit": {"type": "integer", "description": "تعداد در صفحه (پیش‌فرض 20)"},
                },
                "required": [],
            },
            handler=_list_announcements_handler,
            allowed_roles=_ALL_ROLES,
            business_context_required=False,
            required_permissions=[],
            category="user",
        )
    )

    registry.register(
        AIFunction(
            name="list_user_notifications",
            description="لیست اطلاع‌رسانی‌های کاربر جاری (پیامک/ایمیل/درون‌برنامه‌ای).",
            parameters_schema={
                "type": "object",
                "properties": {
                    "search": {"type": "string", "description": "جستجو (اختیاری)"},
                    "skip": {"type": "integer"},
                    "take": {"type": "integer", "description": "تعداد (پیش‌فرض 20)"},
                },
                "required": [],
            },
            handler=_list_user_notifications_handler,
            allowed_roles=_ALL_ROLES,
            business_context_required=False,
            required_permissions=[],
            category="user",
        )
    )


# ============================================================
# handler implementations
# ============================================================

# ---- حسابداری ----
def _list_accounts(db, business_id, user_id, **kwargs):
    from adapters.db.models.account import Account

    q = db.query(Account).filter(
        (Account.business_id == None) | (Account.business_id == business_id)  # noqa: E711
    )
    search = (kwargs.get("search") or "").strip()
    if search:
        term = f"%{search}%"
        q = q.filter((Account.code.ilike(term)) | (Account.name.ilike(term)))
    if kwargs.get("account_type"):
        q = q.filter(Account.account_type == kwargs["account_type"])
    if kwargs.get("parent_id") is not None:
        q = q.filter(Account.parent_id == int(kwargs["parent_id"]))
    rows = q.order_by(Account.code.asc()).all()
    items = [
        {
            "id": r.id,
            "code": r.code,
            "name": r.name,
            "account_type": r.account_type,
            "parent_id": r.parent_id,
            "business_id": r.business_id,
            "is_public": r.business_id is None,
        }
        for r in rows
    ]
    return {"items": items, "total": len(items)}


def _get_account(db, business_id, user_id, account_id, **kwargs):
    from adapters.db.models.account import Account
    from app.services.account_service import account_to_dict

    acc = db.query(Account).filter(
        Account.id == account_id,
        (Account.business_id == None) | (Account.business_id == business_id),  # noqa: E711
    ).first()
    if not acc:
        raise ValueError(f"حساب {account_id} یافت نشد")
    return account_to_dict(acc)


def _create_account_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.account_service import create_account

    db = context["db"]
    business_id = _effective_business_id(args, context)
    return create_account(
        db,
        name=str(args["name"]),
        code=str(args["code"]),
        account_type=str(args["account_type"]),
        business_id=business_id,
        parent_id=int(args["parent_id"]) if args.get("parent_id") is not None else None,
    )


def _update_account_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from adapters.db.models.account import Account
    from app.services.account_service import update_account

    db = context["db"]
    business_id = _effective_business_id(args, context)
    account_id = int(args["account_id"])
    acc = db.query(Account).filter(
        Account.id == account_id, Account.business_id == business_id
    ).first()
    if not acc:
        raise ValueError(f"حساب اختصاصی {account_id} یافت نشد")
    result = update_account(
        db,
        account_id,
        name=args.get("name"),
        code=args.get("code"),
        account_type=args.get("account_type"),
        parent_id=int(args["parent_id"]) if args.get("parent_id") is not None else None,
    )
    if result is None:
        raise ValueError(f"حساب {account_id} یافت نشد")
    return result


def _delete_account_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from adapters.db.models.account import Account
    from app.services.account_service import delete_account

    db = context["db"]
    business_id = _effective_business_id(args, context)
    account_id = int(args["account_id"])
    acc = db.query(Account).filter(
        Account.id == account_id, Account.business_id == business_id
    ).first()
    if not acc:
        raise ValueError(f"حساب اختصاصی {account_id} یافت نشد")
    ok = delete_account(db, account_id)
    return {"deleted": ok, "account_id": account_id}


def _doc_numbering_settings(db, business_id, user_id, **kwargs):
    from adapters.db.models.document_numbering import BusinessDocumentNumberingSetting

    q = db.query(BusinessDocumentNumberingSetting).filter(
        BusinessDocumentNumberingSetting.business_id == business_id
    )
    if kwargs.get("document_type"):
        q = q.filter(BusinessDocumentNumberingSetting.document_type == kwargs["document_type"])
    rows = q.all()
    items = [
        {
            "id": r.id,
            "document_type": r.document_type,
            "prefix": r.prefix,
            "include_date": r.include_date,
            "calendar_type": r.calendar_type,
            "date_format": r.date_format,
            "separator": r.separator,
            "start_number": r.start_number,
            "number_padding": r.number_padding,
            "reset_period": r.reset_period,
            "custom_format": r.custom_format,
            "is_active": r.is_active,
        }
        for r in rows
    ]
    return {"items": items, "total": len(items)}


# ---- انبار / کالا ----
def _list_wh_locations(db, business_id, user_id, warehouse_id, **kwargs):
    from app.services.warehouse_location_service import list_locations_tree

    return list_locations_tree(db, business_id, int(warehouse_id))


def _list_wh_placements(db, business_id, user_id, warehouse_id, **kwargs):
    from app.services.warehouse_location_service import list_placements

    return list_placements(
        db,
        business_id,
        int(warehouse_id),
        product_id=int(kwargs["product_id"]) if kwargs.get("product_id") is not None else None,
        location_id=int(kwargs["location_id"]) if kwargs.get("location_id") is not None else None,
    )


def _warehouse_report(db, business_id, user_id, report_type, **kwargs):
    from app.services import warehouse_reports_service as wr

    skip = int(kwargs.get("skip") or 0)
    take = int(kwargs.get("take") or 50)
    common = {
        "date_from": kwargs.get("from_date"),
        "date_to": kwargs.get("to_date"),
        "warehouse_ids": kwargs.get("warehouse_ids"),
    }
    rtype = str(report_type)

    if rtype == "documents_summary":
        return wr.get_warehouse_documents_summary_report(
            db, business_id, date_from=common["date_from"], date_to=common["date_to"],
            warehouse_ids=common["warehouse_ids"], skip=skip, take=take,
        )
    if rtype == "slow_moving":
        return wr.get_slow_moving_items_report(
            db, business_id,
            days_without_movement=int(kwargs.get("days_without_movement") or 90),
            warehouse_ids=common["warehouse_ids"], category_ids=kwargs.get("category_ids"),
            skip=skip, take=take,
        )
    if rtype == "critical_stock":
        return wr.get_critical_stock_report(
            db, business_id, warehouse_ids=common["warehouse_ids"],
            category_ids=kwargs.get("category_ids"), as_of_date=kwargs.get("as_of_date"),
            skip=skip, take=take,
        )
    if rtype == "inter_warehouse_transfers":
        return wr.get_inter_warehouse_transfers_report(
            db, business_id, date_from=common["date_from"], date_to=common["date_to"],
            skip=skip, take=take,
        )
    if rtype == "adjustments":
        return wr.get_adjustment_documents_report(
            db, business_id, date_from=common["date_from"], date_to=common["date_to"],
            warehouse_ids=common["warehouse_ids"], skip=skip, take=take,
        )
    if rtype == "performance":
        return wr.get_warehouse_performance_report(
            db, business_id, date_from=common["date_from"], date_to=common["date_to"],
            warehouse_ids=common["warehouse_ids"],
        )
    if rtype == "product_movement":
        if kwargs.get("product_id") is None:
            raise ValueError("برای گزارش product_movement باید product_id بدهید")
        return wr.get_product_movement_history_report(
            db, business_id, int(kwargs["product_id"]),
            date_from=common["date_from"], date_to=common["date_to"],
            warehouse_ids=common["warehouse_ids"], skip=skip, take=take,
        )
    if rtype == "valuation":
        return wr.get_inventory_valuation_report(
            db, business_id, as_of_date=kwargs.get("as_of_date"),
            warehouse_ids=common["warehouse_ids"], category_ids=kwargs.get("category_ids"),
            skip=skip, take=take,
        )
    if rtype == "pending":
        return wr.get_pending_documents_report(
            db, business_id, warehouse_ids=common["warehouse_ids"], skip=skip, take=take,
        )
    if rtype == "turnover":
        return wr.get_inventory_turnover_report(
            db, business_id, date_from=common["date_from"], date_to=common["date_to"],
            warehouse_ids=common["warehouse_ids"], category_ids=kwargs.get("category_ids"),
            skip=skip, take=take,
        )
    raise ValueError(f"report_type نامعتبر: {rtype}")


def _list_product_attributes(db, business_id, user_id, **kwargs):
    from app.services.product_attribute_service import list_attributes

    query = {
        "take": kwargs.get("take", 50),
        "skip": kwargs.get("skip", 0),
        "search": kwargs.get("search"),
        "sort_by": kwargs.get("sort_by"),
        "sort_desc": kwargs.get("sort_desc"),
        "filters": kwargs.get("filters"),
    }
    return list_attributes(db, business_id, query)


def _get_product_attribute(db, business_id, user_id, attribute_id, **kwargs):
    from app.services.product_attribute_service import get_attribute

    data = get_attribute(db, int(attribute_id), business_id)
    if not data:
        raise ValueError(f"ویژگی {attribute_id} یافت نشد")
    return data


def _create_product_attribute_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.product_attribute_service import create_attribute
    from adapters.api.v1.schema_models.product_attribute import ProductAttributeCreateRequest

    db = context["db"]
    business_id = _effective_business_id(args, context)
    payload = ProductAttributeCreateRequest(
        title=str(args["title"]),
        description=args.get("description"),
        data_type=args.get("data_type") or "text",
        options=args.get("options"),
    )
    return create_attribute(db, business_id, payload)


def _update_product_attribute_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.product_attribute_service import update_attribute
    from adapters.api.v1.schema_models.product_attribute import ProductAttributeUpdateRequest

    db = context["db"]
    business_id = _effective_business_id(args, context)
    payload = ProductAttributeUpdateRequest(
        title=args.get("title"),
        description=args.get("description"),
        data_type=args.get("data_type"),
        options=args.get("options"),
    )
    result = update_attribute(db, int(args["attribute_id"]), business_id, payload)
    if result is None:
        raise ValueError(f"ویژگی {args['attribute_id']} یافت نشد")
    return result


def _delete_product_attribute_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.product_attribute_service import delete_attribute

    db = context["db"]
    business_id = _effective_business_id(args, context)
    attribute_id = int(args["attribute_id"])
    ok = delete_attribute(db, attribute_id, business_id)
    return {"deleted": ok, "attribute_id": attribute_id}


def _search_product_instances(db, business_id, user_id, **kwargs):
    from adapters.db.models.product_instance import ProductInstance
    from adapters.db.models.product import Product
    from adapters.db.models.warehouse import Warehouse

    q = db.query(ProductInstance).filter(ProductInstance.business_id == business_id)
    if kwargs.get("product_id") is not None:
        q = q.filter(ProductInstance.product_id == int(kwargs["product_id"]))
    if kwargs.get("warehouse_id") is not None:
        q = q.filter(ProductInstance.warehouse_id == int(kwargs["warehouse_id"]))
    if kwargs.get("status"):
        q = q.filter(ProductInstance.status == kwargs["status"])
    if kwargs.get("serial_number"):
        q = q.filter(ProductInstance.serial_number.ilike(f"%{kwargs['serial_number']}%"))
    if kwargs.get("barcode"):
        q = q.filter(ProductInstance.barcode.ilike(f"%{kwargs['barcode']}%"))

    total = q.count()
    skip = int(kwargs.get("skip") or 0)
    take = max(1, min(int(kwargs.get("take") or 50), 200))
    rows = q.order_by(ProductInstance.id.desc()).offset(skip).limit(take).all()

    prod_names = {
        p.id: p.name
        for p in db.query(Product).filter(
            Product.id.in_([r.product_id for r in rows] or [0])
        ).all()
    }
    wh_names = {
        w.id: w.name
        for w in db.query(Warehouse).filter(
            Warehouse.id.in_([r.warehouse_id for r in rows if r.warehouse_id] or [0])
        ).all()
    }
    items = [
        {
            "id": r.id,
            "product_id": r.product_id,
            "product_name": prod_names.get(r.product_id),
            "serial_number": r.serial_number,
            "barcode": r.barcode,
            "warehouse_id": r.warehouse_id,
            "warehouse_name": wh_names.get(r.warehouse_id),
            "status": r.status,
            "custom_attributes": r.custom_attributes,
            "entry_date": r.entry_date.isoformat() if r.entry_date else None,
            "current_invoice_id": r.current_invoice_id,
        }
        for r in rows
    ]
    return {"items": items, "total": total}


# ---- مالی ----
def _list_currency_rates(db, business_id, user_id, **kwargs):
    from app.services.business_currency_rate_service import list_business_currency_rates

    items, total = list_business_currency_rates(
        db,
        business_id,
        currency_id=int(kwargs["currency_id"]) if kwargs.get("currency_id") is not None else None,
        skip=int(kwargs.get("skip") or 0),
        take=max(1, min(int(kwargs.get("take") or 50), 200)),
    )
    return {"items": items, "total": total}


def _resolve_currency_rate(db, business_id, user_id, currency_id, **kwargs):
    from app.services.business_currency_rate_service import resolve_rate_to_base

    as_of = _parse_dt(kwargs.get("as_of_date")) or datetime.utcnow()
    return resolve_rate_to_base(db, business_id, int(currency_id), as_of)


def _list_loan_facilities(db, business_id, user_id, **kwargs):
    from app.services.received_loan_facility_service import list_facilities

    query = {
        "take": max(1, min(int(kwargs.get("take") or 50), 200)),
        "skip": int(kwargs.get("skip") or 0),
        "search": kwargs.get("search") or "",
        "sort_desc": True,
    }
    return list_facilities(db, business_id, query)


def _get_loan_facility(db, business_id, user_id, facility_id, **kwargs):
    from app.services.received_loan_facility_service import get_facility_by_id

    data = get_facility_by_id(
        db, int(facility_id), with_installments=bool(kwargs.get("with_installments"))
    )
    if not data or data.get("business_id") != business_id:
        raise ValueError(f"تسهیل {facility_id} یافت نشد")
    return data


def _wallet_overview(db, business_id, user_id, **kwargs):
    from app.services.wallet_service import get_wallet_overview

    return get_wallet_overview(db, business_id)


def _wallet_transactions(db, business_id, user_id, **kwargs):
    from app.services.wallet_service import list_wallet_transactions

    items = list_wallet_transactions(
        db,
        business_id,
        limit=max(1, min(int(kwargs.get("take") or 50), 200)),
        skip=int(kwargs.get("skip") or 0),
        from_date=_parse_dt(kwargs.get("from_date")),
        to_date=_parse_dt(kwargs.get("to_date")),
    )
    return {"items": items, "total": len(items)}


def _wallet_metrics(db, business_id, user_id, **kwargs):
    from app.services.wallet_service import get_wallet_metrics

    return get_wallet_metrics(
        db,
        business_id,
        from_date=_parse_dt(kwargs.get("from_date")),
        to_date=_parse_dt(kwargs.get("to_date")),
    )


def _list_payment_gateways(db, business_id, user_id, **kwargs):
    from adapters.db.models.payment_gateway import PaymentGateway, BusinessPaymentGateway

    links = db.query(BusinessPaymentGateway).filter(
        BusinessPaymentGateway.business_id == business_id,
        BusinessPaymentGateway.is_active == True,  # noqa: E712
    ).all()
    if links:
        gateway_ids = [l.gateway_id for l in links]
        gateways = db.query(PaymentGateway).filter(
            PaymentGateway.id.in_(gateway_ids), PaymentGateway.is_active == True,  # noqa: E712
        ).all()
    else:
        gateways = db.query(PaymentGateway).filter(
            PaymentGateway.is_active == True  # noqa: E712
        ).all()
    items = [
        {
            "id": g.id,
            "provider": g.provider,
            "display_name": g.display_name,
            "is_sandbox": g.is_sandbox,
        }
        for g in gateways
    ]
    return {"items": items, "total": len(items)}


# ---- ویرایش/حذف اسناد ----
def _update_check_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from adapters.db.models.check import Check
    from app.services.check_service import update_check

    db = context["db"]
    business_id = _effective_business_id(args, context)
    check_id = int(args["check_id"])
    chk = db.query(Check).filter(Check.id == check_id, Check.business_id == business_id).first()
    if not chk:
        raise ValueError(f"چک {check_id} یافت نشد")
    data: Dict[str, Any] = {}
    for key in (
        "type", "person_id", "issue_date", "due_date", "check_number",
        "sayad_code", "bank_name", "branch_name", "amount", "currency_id",
    ):
        if key in args and args[key] is not None:
            data[key] = args[key]
    result = update_check(db, check_id, data)
    if result is None:
        raise ValueError(f"چک {check_id} یافت نشد")
    return result


def _delete_check_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from adapters.db.models.check import Check
    from app.services.check_service import delete_check

    db = context["db"]
    business_id = _effective_business_id(args, context)
    user_id = context["user_context"].get_user_id()
    check_id = int(args["check_id"])
    chk = db.query(Check).filter(Check.id == check_id, Check.business_id == business_id).first()
    if not chk:
        raise ValueError(f"چک {check_id} یافت نشد")
    ok = delete_check(db, check_id, user_id=user_id)
    return {"deleted": ok, "check_id": check_id}


def _assert_business_document(db, document_id: int, business_id: int) -> None:
    from adapters.db.models.document import Document

    doc = db.query(Document).filter(
        Document.id == document_id, Document.business_id == business_id
    ).first()
    if not doc:
        raise ValueError(f"سند {document_id} یافت نشد")


def _update_transfer_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.transfer_service import update_transfer

    db = context["db"]
    business_id = _effective_business_id(args, context)
    user_id = context["user_context"].get_user_id()
    document_id = int(args["document_id"])
    _assert_business_document(db, document_id, business_id)
    data = {
        "document_date": args["document_date"],
        "currency_id": int(args["currency_id"]),
        "amount": float(args["amount"]),
        "description": args.get("description"),
        "source": {"type": args["from_account_type"], "id": int(args["from_account_id"])},
        "destination": {"type": args["to_account_type"], "id": int(args["to_account_id"])},
    }
    if args.get("commission") is not None:
        data["commission"] = float(args["commission"])
    return update_transfer(db, document_id, user_id, data)


def _delete_transfer_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.transfer_service import delete_transfer

    db = context["db"]
    business_id = _effective_business_id(args, context)
    document_id = int(args["document_id"])
    _assert_business_document(db, document_id, business_id)
    ok = delete_transfer(db, document_id)
    return {"deleted": ok, "document_id": document_id}


def _update_receipt_payment_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.ai.ai_tool_payloads import build_update_receipt_payment_payload
    from app.services.receipt_payment_service import update_receipt_payment

    db = context["db"]
    business_id = _effective_business_id(args, context)
    user_id = context["user_context"].get_user_id()
    document_id = int(args["document_id"])
    _assert_business_document(db, document_id, business_id)
    data = build_update_receipt_payment_payload(
        args, db=db, business_id=business_id
    )
    return update_receipt_payment(db, document_id, user_id, data)


def _delete_receipt_payment_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.receipt_payment_service import delete_receipt_payment

    db = context["db"]
    business_id = _effective_business_id(args, context)
    document_id = int(args["document_id"])
    _assert_business_document(db, document_id, business_id)
    ok = delete_receipt_payment(db, document_id)
    return {"deleted": ok, "document_id": document_id}


def _update_expense_income_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.ai.ai_tool_payloads import build_update_expense_income_payload
    from app.services.expense_income_service import update_expense_income

    db = context["db"]
    business_id = _effective_business_id(args, context)
    user_id = context["user_context"].get_user_id()
    document_id = int(args["document_id"])
    _assert_business_document(db, document_id, business_id)
    data = build_update_expense_income_payload(
        args, db=db, business_id=business_id
    )
    return update_expense_income(db, document_id, user_id, data)


def _delete_expense_income_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.expense_income_service import delete_expense_income

    db = context["db"]
    business_id = _effective_business_id(args, context)
    document_id = int(args["document_id"])
    _assert_business_document(db, document_id, business_id)
    ok = delete_expense_income(db, document_id)
    return {"deleted": ok, "document_id": document_id}


# ---- متفرقه ----
def _list_frequent_descriptions(db, business_id, user_id, **kwargs):
    from app.services import business_frequent_description_service as svc

    rows = svc.list_for_business(db, business_id, scope=kwargs.get("scope"))
    items = [svc.to_dict(r) for r in rows]
    return {"items": items, "total": len(items)}


def _list_business_users_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from adapters.db.models.user import User
    from adapters.db.models.business import Business
    from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository

    db = context["db"]
    business_id = _effective_business_id(args, context)
    business = db.get(Business, business_id)
    if not business:
        raise ValueError(f"کسب‌وکار {business_id} یافت نشد")

    users = []
    owner = db.get(User, business.owner_id) if business.owner_id else None
    if owner:
        users.append({
            "user_id": owner.id,
            "user_name": _user_display_name(owner),
            "user_email": getattr(owner, "email", None),
            "user_phone": getattr(owner, "mobile", None),
            "role": "owner",
            "status": "active",
        })

    repo = BusinessPermissionRepository(db)
    for perm in repo.get_business_users(business_id):
        member = db.get(User, perm.user_id)
        users.append({
            "user_id": perm.user_id,
            "user_name": _user_display_name(member),
            "user_email": getattr(member, "email", None) if member else None,
            "user_phone": getattr(member, "mobile", None) if member else None,
            "role": getattr(perm, "role", "member"),
            "status": getattr(perm, "status", None),
        })
    return {"users": users, "total_count": len(users)}


def _list_notification_templates_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from adapters.db.repositories.business_notification_repo import (
        BusinessNotificationTemplateRepository,
    )

    db = context["db"]
    business_id = _effective_business_id(args, context)
    repo = BusinessNotificationTemplateRepository(db)
    filters = {
        k: args[k]
        for k in ("channel", "status", "search")
        if args.get(k) is not None
    }
    rows, total = repo.list_by_business(
        business_id,
        filters=filters or None,
        offset=int(args.get("skip") or 0),
        limit=max(1, min(int(args.get("take") or 50), 200)),
    )
    items = [
        {
            "id": getattr(r, "id", None),
            "event_type": getattr(r, "event_type", None),
            "channel": getattr(r, "channel", None),
            "status": getattr(r, "status", None),
            "is_active": getattr(r, "is_active", None),
        }
        for r in rows
    ]
    return {"items": items, "total": total}


def _list_notification_logs_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from adapters.db.repositories.business_notification_repo import NotificationSendLogRepository

    db = context["db"]
    business_id = _effective_business_id(args, context)
    repo = NotificationSendLogRepository(db)
    filters = {
        k: args[k]
        for k in ("channel", "status")
        if args.get(k) is not None
    }
    rows, total = repo.list_by_business(
        business_id,
        filters=filters or None,
        offset=int(args.get("skip") or 0),
        limit=max(1, min(int(args.get("take") or 50), 200)),
    )
    items = [
        {
            "id": getattr(r, "id", None),
            "channel": getattr(r, "channel", None),
            "status": getattr(r, "status", None),
            "template_id": getattr(r, "template_id", None),
            "created_at": getattr(r, "created_at", None).isoformat()
            if getattr(r, "created_at", None) else None,
        }
        for r in rows
    ]
    return {"items": items, "total": total}


def _list_my_businesses_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.business_service import get_user_businesses

    db = context["db"]
    user_id = context["user_context"].get_user_id()
    query_dict = {
        "take": max(1, min(int(args.get("limit") or 20), 100)),
        "skip": 0,
        "sort_by": "created_at",
        "sort_desc": True,
        "search": args.get("search"),
    }
    result = get_user_businesses(db, user_id, query_dict, include_deleted_for_owner=False)
    items = [
        {
            "id": it.get("id"),
            "name": it.get("name"),
            "role": it.get("role"),
            "is_owner": it.get("is_owner", False),
        }
        for it in (result.get("items") or [])
    ]
    return {"items": items, "total": result.get("pagination", {}).get("total", len(items))}


def _list_announcements_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.announcement_service import user_list

    db = context["db"]
    user_id = context["user_context"].get_user_id()
    return user_list(
        db,
        user_id,
        page=int(args.get("page") or 1),
        limit=max(1, min(int(args.get("limit") or 20), 100)),
        level=args.get("level"),
        only_unread=bool(args.get("only_unread")),
    )


def _list_user_notifications_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from adapters.api.v1.schemas import QueryInfo
    from adapters.db.repositories.notification_outbox_repository import (
        NotificationOutboxRepository,
    )

    db = context["db"]
    user_id = context["user_context"].get_user_id()
    query_info = QueryInfo(
        take=max(1, min(int(args.get("take") or 20), 100)),
        skip=int(args.get("skip") or 0),
        search=args.get("search"),
        sort_by="created_at",
        sort_desc=True,
    )
    rows, total = NotificationOutboxRepository(db).list_for_user(user_id, query_info)
    items = [
        {
            "id": getattr(r, "id", None),
            "channel": getattr(r, "channel", None),
            "event_key": getattr(r, "event_key", None),
            "event_title": getattr(r, "event_title", None),
            "status": getattr(r, "status", None),
            "created_at": getattr(r, "created_at", None).isoformat()
            if getattr(r, "created_at", None) else None,
        }
        for r in rows
    ]
    return {"items": items, "total": total}
