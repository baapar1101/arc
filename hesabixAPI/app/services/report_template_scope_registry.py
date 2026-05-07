from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional, Set, Tuple


@dataclass(frozen=True)
class ScopeMeta:
    module_key: str
    subtype: Optional[str]
    label_fa: str
    label_en: str
    family: str
    supports_builder: bool = True
    allowed_blocks: Optional[Set[str]] = None


_SCOPES: List[ScopeMeta] = [
    ScopeMeta("invoices", "list", "فاکتورها (لیست)", "Invoices (list)", "invoices", allowed_blocks={"text", "image", "table", "divider", "spacer"}),
    ScopeMeta("invoices", "detail", "فاکتور (جزئیات)", "Invoice (detail)", "invoices", allowed_blocks={"text", "image", "table", "divider", "spacer", "qr", "totals"}),
    ScopeMeta("receipts_payments", "list", "دریافت/پرداخت (لیست)", "Receipts/Payments (list)", "receipts_payments", allowed_blocks={"text", "image", "table", "divider", "spacer"}),
    ScopeMeta("receipts_payments", "detail", "دریافت/پرداخت (جزئیات)", "Receipts/Payments (detail)", "receipts_payments", allowed_blocks={"text", "image", "table", "divider", "spacer", "totals"}),
    ScopeMeta("expense_income", "list", "هزینه/درآمد (لیست)", "Expense/Income (list)", "expense_income", allowed_blocks={"text", "image", "table", "divider", "spacer"}),
    ScopeMeta("documents", "list", "اسناد (لیست)", "Documents (list)", "documents", allowed_blocks={"text", "image", "table", "divider", "spacer"}),
    ScopeMeta("documents", "detail", "سند (جزئیات)", "Document (detail)", "documents", allowed_blocks={"text", "image", "table", "divider", "spacer", "totals"}),
    ScopeMeta("transfers", "list", "انتقالات (لیست)", "Transfers (list)", "transfers", allowed_blocks={"text", "image", "table", "divider", "spacer"}),
    ScopeMeta("transfers", "detail", "انتقال (جزئیات)", "Transfer (detail)", "transfers", allowed_blocks={"text", "image", "table", "divider", "spacer", "totals"}),
    ScopeMeta("warehouse_documents", "postal_label", "حواله انبار (برچسب پستی)", "Warehouse document (postal label)", "warehouse_documents", allowed_blocks={"text", "image", "divider", "spacer", "qr"}),
]

_SCOPE_MAP: Dict[Tuple[str, Optional[str]], ScopeMeta] = {
    (s.module_key, s.subtype): s for s in _SCOPES
}


def normalize_scope(module_key: str, subtype: Optional[str]) -> Tuple[str, Optional[str]]:
    mk = (module_key or "").strip()
    st = (subtype or "").strip() or None
    return mk, st


def get_scope_meta(module_key: str, subtype: Optional[str]) -> Optional[ScopeMeta]:
    mk, st = normalize_scope(module_key, subtype)
    return _SCOPE_MAP.get((mk, st))


def is_known_scope(module_key: str, subtype: Optional[str]) -> bool:
    return get_scope_meta(module_key, subtype) is not None


def catalog() -> List[Dict[str, object]]:
    return [
        {
            "module_key": s.module_key,
            "subtype": s.subtype,
            "scope_id": f"{s.module_key}:{s.subtype or 'none'}",
            "family": s.family,
            "label_fa": s.label_fa,
            "label_en": s.label_en,
            "supports_builder": s.supports_builder,
            "allowed_blocks": sorted(list(s.allowed_blocks or set())),
        }
        for s in _SCOPES
    ]
