"""
اجرای queryهای کسب‌وکار برای AI — reuse از service layer و workflow query helpers.
"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from app.core.auth_dependency import AuthContext

logger = logging.getLogger(__name__)

# موجودیت‌های پشتیبانی‌شده در query_business_data (فاز ۱؛ فاز ۲ در انتهای فایل merge می‌شود)
_SUPPORTED_ENTITIES_PHASE1 = frozenset({
    "warehouse_document",
    "warehouse",
    "check",
    "transfer",
    "expense_income",
    "document",
    "invoice",
    "bank_account",
    "cash_register",
    "fiscal_year",
    "person_transaction",
})
SUPPORTED_ENTITIES = _SUPPORTED_ENTITIES_PHASE1

SUPPORTED_ACTIONS = frozenset({"search", "list", "get", "count"})

ENTITY_READ_PERMISSIONS: Dict[str, List[str]] = {
    "warehouse_document": ["warehouses.view", "inventory.read"],
    "warehouse": ["warehouses.view", "inventory.read"],
    "check": ["checks.view"],
    "transfer": ["transfers.view", "accounting_documents.view"],
    "expense_income": ["expenses_income.view", "accounting_documents.view"],
    "document": ["accounting_documents.view"],
    "invoice": ["invoices.read"],
    "bank_account": ["bank_accounts.view"],
    "cash_register": ["cash_registers.view"],
    "fiscal_year": ["fiscal_years.view"],
    "person_transaction": ["persons.read", "reports.read"],
}


def _to_int(v: Any, default: Optional[int] = None) -> Optional[int]:
    if v is None or v == "":
        return default
    try:
        return int(v)
    except (TypeError, ValueError):
        return default


def _clamp_pagination(filters: Dict[str, Any], *, default_take: int = 50, max_take: int = 200) -> Dict[str, Any]:
    take = max(1, min(_to_int(filters.get("take"), default_take) or default_take, max_take))
    skip = max(0, _to_int(filters.get("skip"), 0) or 0)
    out = dict(filters)
    out["take"] = take
    out["skip"] = skip
    return out


def _build_list_query(filters: Dict[str, Any], *, entity: Optional[str] = None) -> Dict[str, Any]:
    """نگاشت filters عمومی به query dict سرویس‌ها (شامل filters[] پیشرفته)."""
    from app.services.ai.ai_query_filter_service import merge_into_query_dict

    merged = merge_into_query_dict(filters or {}, entity=entity)
    q = _clamp_pagination(merged)
    for key in (
        "search",
        "search_fields",
        "filters",
        "sort",
        "from_date",
        "to_date",
        "document_type",
        "doc_type",
        "status",
        "fiscal_year_id",
        "person_id",
        "warehouse_id",
        "currency_id",
        "is_proforma",
        "sort_by",
        "sort_desc",
        "account_type",
        "type",
    ):
        if merged.get(key) is not None:
            q[key] = merged[key]
    return q


def query_business_data(
    db: Session,
    business_id: int,
    user_context: AuthContext,
    *,
    entity: str,
    action: str = "search",
    filters: Optional[Dict[str, Any]] = None,
    record_id: Optional[int] = None,
) -> Any:
    """
    ابزار جنریک: entity + action + filters.

    action:
      - search/list: لیست با صفحه‌بندی
      - get: یک رکورد (record_id یا filters.id)
      - count: تعداد (فقط pagination.total)
    """
    entity_key = (entity or "").strip().lower()
    action_key = (action or "search").strip().lower()
    if entity_key not in SUPPORTED_ENTITIES:
        raise ValueError(
            f"entity نامعتبر: {entity_key}. مقادیر مجاز: {', '.join(sorted(SUPPORTED_ENTITIES))}"
        )
    if action_key not in SUPPORTED_ACTIONS:
        raise ValueError(
            f"action نامعتبر: {action_key}. مقادیر مجاز: {', '.join(sorted(SUPPORTED_ACTIONS))}"
        )

    perms = ENTITY_READ_PERMISSIONS.get(entity_key, [])
    if perms:
        from app.services.ai.ai_permission_map import has_any_ai_tool_permission

        if not has_any_ai_tool_permission(
            user_context, perms, business_id=business_id
        ):
            raise PermissionError(f"دسترسی به {entity_key} وجود ندارد")

    flt = dict(filters or {})
    try:
        from app.services.ai.ai_query_filter_service import merge_into_query_dict

        flt = merge_into_query_dict(flt, entity=entity_key)
    except ValueError as exc:
        raise ValueError(str(exc)) from exc

    rid = record_id if record_id is not None else _to_int(flt.get("id") or flt.get("record_id"))

    if action_key == "get":
        return _entity_get(db, business_id, entity_key, rid, flt, user_context)

    data = _entity_search(db, business_id, entity_key, flt, user_context)
    if action_key == "count":
        total = 0
        if isinstance(data, dict):
            pag = data.get("pagination") or {}
            total = pag.get("total", data.get("total", 0))
        return {"total": total, "entity": entity_key, "filters_applied": flt}
    return data


def _entity_search(
    db: Session,
    business_id: int,
    entity: str,
    filters: Dict[str, Any],
    user_context: Optional[AuthContext] = None,
) -> Any:
    if entity in _PHASE4_ENTITIES:
        return _phase4_entity_search(db, business_id, entity, filters, user_context)
    if entity in _PHASE3_ENTITIES:
        return _phase3_entity_search(db, business_id, entity, filters, user_context)
    if entity in _PHASE2_ENTITIES:
        return _phase2_entity_search(db, business_id, entity, filters, user_context)
    if entity == "warehouse_document":
        from app.services.workflow.actions.hesabix_query_actions import (
            _search_warehouse_documents_internal,
        )

        body = _build_list_query(filters, entity=entity)
        return _search_warehouse_documents_internal(db, business_id, body)

    if entity == "warehouse":
        from app.services.warehouse_service import list_warehouses

        return list_warehouses(db, business_id)

    if entity == "check":
        from app.services.check_service import list_checks

        q = _build_list_query(filters, entity=entity)
        if q.get("search") and not q.get("search_fields"):
            q["search_fields"] = [
                "check_number",
                "sayad_code",
                "bank_name",
                "branch_name",
                "person_name",
            ]
        return list_checks(db, business_id, q)

    if entity == "transfer":
        from app.services.transfer_service import list_transfers

        q = _build_list_query(filters, entity=entity)
        if q.get("search") and not q.get("search_fields"):
            q["search_fields"] = ["code", "description", "created_by_name"]
        return list_transfers(db, business_id, q)

    if entity == "expense_income":
        from app.services.expense_income_service import list_expense_income

        q = _build_list_query(filters, entity=entity)
        if q.get("search") and not q.get("search_fields"):
            q["search_fields"] = ["code", "description", "created_by_name"]
        return list_expense_income(db, business_id, q)

    if entity == "document":
        from app.services.document_service import list_documents

        q = _build_list_query(filters, entity=entity)
        return list_documents(db, business_id, q)

    if entity == "invoice":
        from app.services.workflow.actions.hesabix_query_actions import (
            _list_invoices_workflow,
        )

        return _list_invoices_workflow(db, business_id, _build_list_query(filters, entity=entity))

    if entity == "bank_account":
        from app.services.bank_account_service import list_bank_accounts

        q = _build_list_query(filters, entity=entity)
        if q.get("search") and not q.get("search_fields"):
            q["search_fields"] = ["code", "name", "branch", "account_number", "owner_name"]
        return list_bank_accounts(db, business_id, q)

    if entity == "cash_register":
        from app.services.cash_register_service import list_cash_registers

        q = _build_list_query(filters, entity=entity)
        if q.get("search") and not q.get("search_fields"):
            q["search_fields"] = ["code", "name"]
        return list_cash_registers(db, business_id, q)

    if entity == "fiscal_year":
        return list_fiscal_years_data(db, business_id)

    if entity == "person_transaction":
        from app.services.person_service import get_people_transactions_report

        q = _clamp_pagination(filters, default_take=50)
        person_ids = None
        pid = _to_int(filters.get("person_id"))
        if pid is not None:
            person_ids = [pid]
        return get_people_transactions_report(
            db,
            business_id,
            fiscal_year_id=_to_int(filters.get("fiscal_year_id")),
            currency_id=_to_int(filters.get("currency_id")),
            date_from=filters.get("from_date") or filters.get("date_from"),
            date_to=filters.get("to_date") or filters.get("date_to"),
            person_ids=person_ids,
            document_type=filters.get("document_type") or filters.get("type"),
            search=filters.get("search"),
            skip=q["skip"],
            take=q["take"],
        )

    raise ValueError(f"entity پیاده‌سازی نشده: {entity}")


def _entity_get(
    db: Session,
    business_id: int,
    entity: str,
    record_id: Optional[int],
    filters: Dict[str, Any],
    user_context: Optional[AuthContext] = None,
) -> Any:
    if entity in _PHASE4_ENTITIES:
        return _phase4_entity_get(db, business_id, entity, record_id, filters, user_context)
    if entity in _PHASE3_ENTITIES:
        return _phase3_entity_get(db, business_id, entity, record_id, filters, user_context)
    if entity in _PHASE2_ENTITIES:
        return _phase2_entity_get(db, business_id, entity, record_id, filters, user_context)

    rid = record_id or _to_int(filters.get("warehouse_document_id") or filters.get("check_id"))
    if rid is None:
        rid = _to_int(
            filters.get("transfer_id")
            or filters.get("document_id")
            or filters.get("warehouse_id")
        )

    if entity == "warehouse_document":
        from adapters.db.models.warehouse_document import WarehouseDocument
        from app.services.warehouse_service import warehouse_document_to_dict

        doc_id = rid or _to_int(filters.get("id"))
        if doc_id is None:
            raise ValueError("warehouse_document_id یا id الزامی است")
        wh = (
            db.query(WarehouseDocument)
            .filter(
                WarehouseDocument.id == doc_id,
                WarehouseDocument.business_id == business_id,
            )
            .first()
        )
        if not wh:
            raise ValueError(f"حواله انبار {doc_id} یافت نشد")
        return warehouse_document_to_dict(db, wh)

    if entity == "warehouse":
        from app.services.warehouse_service import get_warehouse

        wid = rid or _to_int(filters.get("id"))
        if wid is None:
            raise ValueError("warehouse_id الزامی است")
        data = get_warehouse(db, business_id, wid)
        if not data:
            raise ValueError(f"انبار {wid} یافت نشد")
        return data

    if entity == "check":
        from app.services.check_service import get_check_by_id
        from adapters.db.models.check import Check

        cid = rid or _to_int(filters.get("id"))
        if cid is None:
            raise ValueError("check_id الزامی است")
        chk = db.query(Check).filter(Check.id == cid, Check.business_id == business_id).first()
        if not chk:
            raise ValueError(f"چک {cid} یافت نشد")
        return get_check_by_id(db, cid)

    if entity == "transfer":
        from app.services.transfer_service import get_transfer
        from adapters.db.models.document import Document

        tid = rid or _to_int(filters.get("id"))
        if tid is None:
            raise ValueError("transfer_id یا document_id الزامی است")
        doc = db.query(Document).filter(
            Document.id == tid, Document.business_id == business_id
        ).first()
        if not doc:
            raise ValueError(f"انتقال {tid} یافت نشد")
        data = get_transfer(db, tid)
        if not data:
            raise ValueError(f"انتقال {tid} یافت نشد")
        return data

    if entity == "document":
        from app.services.document_service import get_document
        from adapters.db.models.document import Document

        did = rid or _to_int(filters.get("id"))
        if did is None:
            raise ValueError("document_id الزامی است")
        doc = db.query(Document).filter(
            Document.id == did, Document.business_id == business_id
        ).first()
        if not doc:
            raise ValueError(f"سند {did} یافت نشد")
        data = get_document(db, did)
        if not data:
            raise ValueError(f"سند {did} یافت نشد")
        return data

    if entity == "invoice":
        from app.services.invoice_service import invoice_document_to_dict
        from adapters.db.models.document import Document
        from app.services.invoice_service import SUPPORTED_INVOICE_TYPES

        iid = rid or _to_int(filters.get("invoice_id") or filters.get("id"))
        if iid is None:
            raise ValueError("invoice_id الزامی است")
        document = (
            db.query(Document)
            .filter(Document.id == iid, Document.business_id == business_id)
            .first()
        )
        if not document or document.document_type not in SUPPORTED_INVOICE_TYPES:
            raise ValueError(f"فاکتور {iid} یافت نشد")
        return invoice_document_to_dict(db, document)

    if entity == "fiscal_year":
        return get_current_fiscal_year_data(db, business_id)

    raise ValueError(f"get برای entity «{entity}» پشتیبانی نمی‌شود")


def list_fiscal_years_data(db: Session, business_id: int) -> Dict[str, Any]:
    from adapters.db.repositories.fiscal_year_repo import FiscalYearRepository

    repo = FiscalYearRepository(db)
    items = repo.list_by_business(business_id)
    data = [
        {
            "id": fy.id,
            "title": fy.title,
            "start_date": fy.start_date.isoformat() if fy.start_date else None,
            "end_date": fy.end_date.isoformat() if fy.end_date else None,
            "is_current": bool(fy.is_last),
        }
        for fy in items
    ]
    current = next((x for x in data if x.get("is_current")), None)
    return {"items": data, "current": current, "total": len(data)}


def get_current_fiscal_year_data(db: Session, business_id: int) -> Dict[str, Any]:
    from adapters.db.repositories.fiscal_year_repo import FiscalYearRepository

    repo = FiscalYearRepository(db)
    fy = repo.get_current_for_business(business_id)
    if not fy:
        return {"current": None, "message": "سال مالی جاری تعریف نشده"}
    return {
        "current": {
            "id": fy.id,
            "title": fy.title,
            "start_date": fy.start_date.isoformat() if fy.start_date else None,
            "end_date": fy.end_date.isoformat() if fy.end_date else None,
            "is_current": True,
        }
    }


def get_business_dashboard_summary(
    db: Session,
    business_id: int,
    user_context: AuthContext,
) -> Dict[str, Any]:
    from app.services.business_dashboard_service import get_business_dashboard_data

    return get_business_dashboard_data(db, business_id, user_context)


def get_warehouse_stock_summary(
    db: Session,
    business_id: int,
    filters: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    from app.services.warehouse_service import get_warehouse_stock_report

    flt = filters or {}
    query = {
        "product_ids": flt.get("product_ids") or [],
        "warehouse_ids": flt.get("warehouse_ids") or [],
        "as_of_date": flt.get("as_of_date"),
        "include_zero": bool(flt.get("include_zero", False)),
    }
    if flt.get("product_id"):
        query["product_ids"] = [int(flt["product_id"])]
    if flt.get("warehouse_id"):
        query["warehouse_ids"] = [int(flt["warehouse_id"])]
    return get_warehouse_stock_report(db, business_id, query)


# --- ادغام فاز ۲ (import در انتها برای جلوگیری از circular import) ---
from app.services.ai.ai_query_phase2_service import (  # noqa: E402
    PHASE2_ENTITIES as _PHASE2_ENTITIES,
    PHASE2_ENTITY_PERMISSIONS,
    phase2_entity_get as _phase2_entity_get,
    phase2_entity_search as _phase2_entity_search,
)

from app.services.ai.ai_query_phase3_service import (  # noqa: E402
    PHASE3_ENTITIES as _PHASE3_ENTITIES,
    PHASE3_ENTITY_PERMISSIONS,
    phase3_entity_get as _phase3_entity_get,
    phase3_entity_search as _phase3_entity_search,
)

from app.services.ai.ai_query_phase4_service import (  # noqa: E402
    PHASE4_ENTITIES as _PHASE4_ENTITIES,
    PHASE4_ENTITY_PERMISSIONS,
    phase4_entity_get as _phase4_entity_get,
    phase4_entity_search as _phase4_entity_search,
)

SUPPORTED_ENTITIES = (
    _SUPPORTED_ENTITIES_PHASE1 | _PHASE2_ENTITIES | _PHASE3_ENTITIES | _PHASE4_ENTITIES
)
ENTITY_READ_PERMISSIONS = {
    **ENTITY_READ_PERMISSIONS,
    **PHASE2_ENTITY_PERMISSIONS,
    **PHASE3_ENTITY_PERMISSIONS,
    **PHASE4_ENTITY_PERMISSIONS,
}
