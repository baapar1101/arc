"""
کاتالوگ فیلدهای قابل جستجو/فیلتر برای entityهای AI (فاز ۱۰).
فقط فیلدهایی که در سرویس backend تأیید شده‌اند.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

# عملگرهای استاندارد QueryInfo / QueryBuilder
STANDARD_OPERATORS: Tuple[str, ...] = (
    "=",
    "!=",
    ">",
    ">=",
    "<",
    "<=",
    "*",
    "*?",
    "?*",
    "in",
)


@dataclass(frozen=True)
class FieldSpec:
    property: str
    label_fa: str
    type: str  # string, number, date, boolean, enum
    operators: Tuple[str, ...] = STANDARD_OPERATORS
    enum_values: Optional[Tuple[str, ...]] = None
    notes: str = ""


@dataclass(frozen=True)
class EntityQuerySpec:
    entity: str
    label_fa: str
    search_fields_default: Tuple[str, ...]
    filterable_fields: Tuple[FieldSpec, ...]
    flat_filters: Tuple[str, ...] = ()  # from_date, person_id, ...


ENTITY_QUERY_SPECS: Dict[str, EntityQuerySpec] = {
    "invoice": EntityQuerySpec(
        entity="invoice",
        label_fa="فاکتور / سند",
        search_fields_default=("code", "description", "created_by_name"),
        flat_filters=("from_date", "to_date", "document_type", "fiscal_year_id", "person_id", "is_proforma"),
        filterable_fields=(
            FieldSpec("document_type", "نوع سند", "enum", enum_values=(
                "invoice_sales", "invoice_purchase", "invoice_sales_return", "invoice_purchase_return",
            )),
            FieldSpec("document_date", "تاریخ سند", "date"),
            FieldSpec("code", "کد سند", "string"),
            FieldSpec("description", "شرح", "string"),
            FieldSpec("is_proforma", "پیش‌فاکتور", "boolean", operators=("=",)),
            FieldSpec("project_name", "پروژه (شناسه در value)", "number", notes="مقدار = project_id"),
        ),
    ),
    "document": EntityQuerySpec(
        entity="document",
        label_fa="اسناد حسابداری",
        search_fields_default=("code", "description", "created_by_name"),
        flat_filters=("from_date", "to_date", "document_type", "fiscal_year_id"),
        filterable_fields=(
            FieldSpec("document_type", "نوع سند", "string"),
            FieldSpec("document_date", "تاریخ", "date"),
            FieldSpec("code", "کد", "string"),
            FieldSpec("description", "شرح", "string"),
        ),
    ),
    "person": EntityQuerySpec(
        entity="person",
        label_fa="اشخاص",
        search_fields_default=("code", "alias_name", "first_name", "last_name", "mobile", "email", "national_id"),
        flat_filters=("person_id",),
        filterable_fields=(
            FieldSpec("alias_name", "نام مستعار", "string"),
            FieldSpec("first_name", "نام", "string"),
            FieldSpec("last_name", "نام خانوادگی", "string"),
            FieldSpec("company_name", "نام شرکت", "string"),
            FieldSpec("mobile", "موبایل", "string"),
            FieldSpec("email", "ایمیل", "string"),
            FieldSpec("national_id", "کد ملی", "string"),
            FieldSpec("person_types", "نوع شخص", "string", notes='مثلاً customer — عملگر * یا in'),
            FieldSpec("is_active", "فعال", "boolean", operators=("=",)),
            FieldSpec("balance", "مانده", "number", notes="نیاز به materialization در سرویس"),
            FieldSpec("status", "وضعیت بدهکار/بستانکار", "string", operators=("=", "in")),
        ),
    ),
    "check": EntityQuerySpec(
        entity="check",
        label_fa="چک",
        search_fields_default=("check_number", "sayad_code", "bank_name", "person_name"),
        flat_filters=("from_date", "to_date", "status"),
        filterable_fields=(
            FieldSpec("check_number", "شماره چک", "string"),
            FieldSpec("amount", "مبلغ", "number"),
            FieldSpec("due_date", "سررسید", "date"),
            FieldSpec("status", "وضعیت", "string"),
            FieldSpec("type", "نوع", "string"),
        ),
    ),
    "transfer": EntityQuerySpec(
        entity="transfer",
        label_fa="انتقال",
        search_fields_default=("code", "description", "created_by_name"),
        flat_filters=("from_date", "to_date"),
        filterable_fields=(
            FieldSpec("code", "کد", "string"),
            FieldSpec("document_date", "تاریخ", "date"),
            FieldSpec("description", "شرح", "string"),
        ),
    ),
    "expense_income": EntityQuerySpec(
        entity="expense_income",
        label_fa="هزینه / درآمد",
        search_fields_default=("code", "description", "created_by_name"),
        flat_filters=("from_date", "to_date", "document_type"),
        filterable_fields=(
            FieldSpec("document_type", "نوع", "enum", enum_values=("expense", "income"), operators=("=", "in")),
            FieldSpec("document_date", "تاریخ", "date"),
            FieldSpec("code", "کد", "string"),
        ),
    ),
    "warehouse_document": EntityQuerySpec(
        entity="warehouse_document",
        label_fa="حواله انبار",
        search_fields_default=("code", "description"),
        flat_filters=("from_date", "to_date", "warehouse_id", "doc_type"),
        filterable_fields=(
            FieldSpec("code", "کد", "string"),
            FieldSpec("document_date", "تاریخ", "date"),
            FieldSpec("status", "وضعیت", "string"),
        ),
    ),
    "bank_account": EntityQuerySpec(
        entity="bank_account",
        label_fa="حساب بانکی",
        search_fields_default=("code", "name", "branch", "account_number"),
        flat_filters=(),
        filterable_fields=(
            FieldSpec("name", "نام", "string"),
            FieldSpec("code", "کد", "string"),
            FieldSpec("is_active", "فعال", "boolean", operators=("=",)),
        ),
    ),
    "cash_register": EntityQuerySpec(
        entity="cash_register",
        label_fa="صندوق",
        search_fields_default=("code", "name"),
        flat_filters=(),
        filterable_fields=(
            FieldSpec("name", "نام", "string"),
            FieldSpec("code", "کد", "string"),
        ),
    ),
    "product": EntityQuerySpec(
        entity="product",
        label_fa="کالا و خدمات",
        search_fields_default=("code", "name", "barcode"),
        flat_filters=("category_id",),
        filterable_fields=(
            FieldSpec("code", "کد", "string"),
            FieldSpec("name", "نام", "string"),
            FieldSpec("item_type", "نوع", "enum", enum_values=("product", "service"), operators=("=", "in")),
            FieldSpec("track_inventory", "کنترل موجودی", "boolean", operators=("=",)),
            FieldSpec("base_sales_price", "قیمت فروش", "number"),
            FieldSpec("base_purchase_price", "قیمت خرید", "number"),
            FieldSpec("is_active", "فعال", "boolean", operators=("=",)),
        ),
    ),
}


def get_entity_query_spec(entity: str) -> Optional[EntityQuerySpec]:
    return ENTITY_QUERY_SPECS.get((entity or "").strip().lower())


def list_catalog_entities() -> List[str]:
    return sorted(ENTITY_QUERY_SPECS.keys())
