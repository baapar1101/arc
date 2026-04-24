"""
اکشن‌های «مرکز داده» — جستجو/لیست/جزئیات از موجودیت‌های هسابیکس (مشابه Data Table در n8n)
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from sqlalchemy import and_, or_, desc, asc
from sqlalchemy.orm import Session

from app.services.workflow.action_registry import ActionHandler
from app.services.workflow.logging_decorators import log_action_execution
from app.services.workflow.workflow_engine import WorkflowEngine

logger = logging.getLogger(__name__)


def _to_int(v: Any, default: Optional[int] = None) -> Optional[int]:
    if v is None or v == "":
        return default
    try:
        return int(v)
    except (TypeError, ValueError):
        return default


def _search_warehouse_documents_internal(
    db: Session, business_id: int, body: Dict[str, Any]
) -> Dict[str, Any]:
    """همان منطق جستجوی حواله انبار (بدون cache و بدون request)."""
    from adapters.db.models.warehouse_document import WarehouseDocument
    from app.services.warehouse_service import warehouse_document_to_dict
    from app.services.transfer_service import _parse_iso_date as _parse_date
    from app.services.sort_resolution import effective_sort_specs
    from adapters.api.v1.schemas import QueryInfo

    q = db.query(WarehouseDocument).filter(WarehouseDocument.business_id == business_id)

    doc_type = body.get("doc_type")
    if isinstance(doc_type, str) and doc_type:
        q = q.filter(WarehouseDocument.doc_type == doc_type)
    elif isinstance(body.get("doc_type"), list):
        dtl = body.get("doc_type")
        if dtl:
            q = q.filter(WarehouseDocument.doc_type.in_(dtl))

    status = body.get("status")
    if isinstance(status, str) and status:
        q = q.filter(WarehouseDocument.status == status)
    elif isinstance(body.get("status"), list):
        sl = body.get("status")
        if sl:
            q = q.filter(WarehouseDocument.status.in_(sl))

    source_document_id = body.get("source_document_id")
    if isinstance(source_document_id, int):
        q = q.filter(WarehouseDocument.source_document_id == source_document_id)

    source_type = body.get("source_type")
    if isinstance(source_type, str) and source_type:
        q = q.filter(WarehouseDocument.source_type == source_type)

    from_date, to_date = body.get("from_date"), body.get("to_date")
    try:
        if isinstance(from_date, str) and from_date:
            q = q.filter(WarehouseDocument.document_date >= _parse_date(from_date))
        if isinstance(to_date, str) and to_date:
            q = q.filter(WarehouseDocument.document_date <= _parse_date(to_date))
    except Exception:
        pass

    warehouse_id = body.get("warehouse_id")
    warehouse_ids = body.get("warehouse_ids")
    if warehouse_id:
        q = q.filter(
            or_(
                WarehouseDocument.warehouse_id_from == int(warehouse_id),
                WarehouseDocument.warehouse_id_to == int(warehouse_id),
            )
        )
    elif isinstance(warehouse_ids, list) and warehouse_ids:
        wh_ids = [int(w) for w in warehouse_ids if w]
        if wh_ids:
            q = q.filter(
                or_(
                    WarehouseDocument.warehouse_id_from.in_(wh_ids),
                    WarehouseDocument.warehouse_id_to.in_(wh_ids),
                )
            )

    search = body.get("search")
    if isinstance(search, str) and search.strip():
        st = f"%{search.strip()}%"
        q = q.filter(WarehouseDocument.code.like(st))

    _WH_SORT_ALLOWED = frozenset({"code", "doc_type", "status", "created_at", "document_date"})

    def _wh_sort_col(name: str):
        if name == "code":
            return WarehouseDocument.code
        if name == "doc_type":
            return WarehouseDocument.doc_type
        if name == "status":
            return WarehouseDocument.status
        if name == "created_at":
            return WarehouseDocument.created_at
        return WarehouseDocument.document_date

    _qi = QueryInfo.model_validate({
        "take": int(body.get("take", 20) or 20),
        "skip": int(body.get("skip", 0) or 0),
        "sort_by": body.get("sort_by"),
        "sort_desc": bool(body.get("sort_desc", True)),
        "sort": body.get("sort") if isinstance(body.get("sort"), list) else None,
    })
    _specs = effective_sort_specs(_qi, allowed=_WH_SORT_ALLOWED, default_when_empty=("document_date", True))
    _order_parts = []
    for _n, _d in _specs:
        _c = _wh_sort_col(_n)
        _order_parts.append(_c.desc() if _d else _c.asc())
    _order_parts.append(WarehouseDocument.id.desc())
    q = q.order_by(*_order_parts)

    take = int(body.get("take") or 20)
    skip = int(body.get("skip") or 0)
    total = q.count()
    items = q.offset(skip).limit(take).all()

    return {
        "items": [warehouse_document_to_dict(db, wh) for wh in items],
        "pagination": {
            "total": total,
            "page": (skip // max(1, take)) + 1,
            "per_page": take,
            "total_pages": (total + take - 1) // max(1, take),
            "has_next": skip + take < total,
            "has_prev": skip > 0,
        },
    }


def _list_invoices_workflow(
    db: Session, business_id: int, config: Dict[str, Any]
) -> Dict[str, Any]:
    from adapters.db.models.document import Document
    from app.services.invoice_service import SUPPORTED_INVOICE_TYPES, invoice_document_to_dict

    take = max(1, min(int(config.get("take", 20) or 20), 500))
    skip = max(0, int(config.get("skip", 0) or 0))

    q = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type.in_(list(SUPPORTED_INVOICE_TYPES)),
        )
    )

    doc_type = config.get("document_type")
    if isinstance(doc_type, str) and doc_type in SUPPORTED_INVOICE_TYPES:
        q = q.filter(Document.document_type == doc_type)

    is_proforma = config.get("is_proforma")
    if isinstance(is_proforma, bool):
        q = q.filter(Document.is_proforma == is_proforma)

    currency_id = _to_int(config.get("currency_id"))
    if currency_id is not None:
        q = q.filter(Document.currency_id == currency_id)

    fiscal_year_id = _to_int(config.get("fiscal_year_id"))
    if fiscal_year_id is not None:
        q = q.filter(Document.fiscal_year_id == fiscal_year_id)

    from_date, to_date = config.get("from_date"), config.get("to_date")
    if isinstance(from_date, str) and from_date:
        from app.services.receipt_payment_service import _parse_iso_date
        try:
            q = q.filter(Document.document_date >= _parse_iso_date(from_date))
        except Exception:
            pass
    if isinstance(to_date, str) and to_date:
        from app.services.receipt_payment_service import _parse_iso_date
        try:
            q = q.filter(Document.document_date <= _parse_iso_date(to_date))
        except Exception:
            pass

    search = config.get("search")
    if isinstance(search, str) and search.strip():
        pat = f"%{search.strip()}%"
        q = q.filter(
            or_(
                Document.code.ilike(pat),
                Document.description.ilike(pat),
            )
        )

    person_id = _to_int(config.get("person_id"))
    if person_id is not None:
        from adapters.db.models.document_line import DocumentLine
        from sqlalchemy import exists
        q = q.filter(
            exists().where(
                and_(
                    DocumentLine.document_id == Document.id,
                    DocumentLine.person_id == person_id,
                )
            )
        )

    total = q.count()
    sort_by = config.get("sort_by") or "document_date"
    sort_desc = bool(config.get("sort_desc", True))
    col = Document.document_date
    if sort_by == "code":
        col = Document.code
    elif sort_by == "created_at":
        col = Document.created_at
    elif sort_by == "id":
        col = Document.id
    if sort_desc:
        q = q.order_by(desc(col), desc(Document.id))
    else:
        q = q.order_by(asc(col), asc(Document.id))

    rows = q.offset(skip).limit(take).all()
    items: List[Dict[str, Any]] = []
    for doc in rows:
        try:
            items.append(invoice_document_to_dict(db, doc))
        except Exception as e:
            logger.warning("invoice_document_to_dict failed id=%s: %s", doc.id, e)
            items.append({"id": doc.id, "document_type": doc.document_type, "error": str(e)})

    return {
        "items": items,
        "pagination": {
            "total": total,
            "page": (skip // take) + 1,
            "per_page": take,
            "total_pages": (total + take - 1) // take,
            "has_next": (skip + take) < total,
            "has_prev": skip > 0,
        },
    }


class BaseHesabixQueryAction(ActionHandler):
    """پایه با resolve کردن config"""

    def _resolve_cfg(
        self, config: Dict[str, Any], context: Dict[str, Any], node_results: Dict[str, Any]
    ) -> Dict[str, Any]:
        out: Dict[str, Any] = {}
        for k, v in (config or {}).items():
            out[k] = WorkflowEngine._resolve_value_static(v, context, node_results)
        return out


class QueryPersonsAction(BaseHesabixQueryAction):
    @log_action_execution
    def execute(self, context, config, node_results):
        from app.services.person_service import get_persons_by_business

        db = context.get("db")
        business_id = context.get("business_id")
        cfg = self._resolve_cfg(config, context, node_results)
        search = cfg.get("search")
        take = max(1, min(int(cfg.get("take", 20) or 20), 500))
        skip = max(0, int(cfg.get("skip", 0) or 0))
        qinfo: Dict[str, Any] = {
            "take": take,
            "skip": skip,
            "sort_by": cfg.get("sort_by") or "created_at",
            "sort_desc": bool(cfg.get("sort_desc", True)),
        }
        if search:
            qinfo["search"] = str(search)
            qinfo["search_fields"] = [
                "alias_name", "first_name", "last_name", "company_name",
                "mobile", "email", "code", "phone",
            ]
        return {
            "success": True,
            "data": get_persons_by_business(
                db, int(business_id), qinfo,
                fiscal_year_id=_to_int(cfg.get("fiscal_year_id")),
            ),
        }

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "لیست اشخاص",
            "description": "جستجو و صفحه‌بندی لیست اشخاص کسب‌وکار",
            "config_schema": {
                "search": {"type": "string", "description": "متن جستجو (اختیاری)", "required": False},
                "take": {"type": "integer", "description": "تعداد نتیجه (حداکثر ۵۰۰)", "default": 20, "required": False},
                "skip": {"type": "integer", "description": "offset", "default": 0, "required": False},
                "sort_by": {"type": "string", "description": "مرتب‌سازی", "required": False},
                "sort_desc": {"type": "boolean", "default": True, "required": False},
                "fiscal_year_id": {"type": "integer", "description": "سال مالی برای تراز (اختیاری)", "required": False, "ui_type": "fiscal_year_selector", "ui_config": {"business_scoped": True}},
            },
        }


class QueryPersonAction(BaseHesabixQueryAction):
    @log_action_execution
    def execute(self, context, config, node_results):
        from app.services.person_service import get_person_by_id

        db = context.get("db")
        business_id = context.get("business_id")
        cfg = self._resolve_cfg(config, context, node_results)
        pid = _to_int(cfg.get("person_id"))
        if pid is None:
            return {"success": False, "error": "person_id is required"}
        data = get_person_by_id(
            db, pid, int(business_id), fiscal_year_id=_to_int(cfg.get("fiscal_year_id")),
        )
        if not data:
            return {"success": False, "error": "PERSON_NOT_FOUND", "person_id": pid}
        return {"success": True, "data": data}

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "جزئیات شخص",
            "description": "دریافت یک شخص بر اساس شناسه",
            "config_schema": {
                "person_id": {"type": "integer", "description": "شناسه شخص", "required": True},
                "fiscal_year_id": {"type": "integer", "description": "سال مالی تراز (اختیاری)", "required": False, "ui_type": "fiscal_year_selector", "ui_config": {"business_scoped": True}},
            },
        }


class QueryProductsAction(BaseHesabixQueryAction):
    @log_action_execution
    def execute(self, context, config, node_results):
        from app.services.product_service import list_products

        db = context.get("db")
        business_id = context.get("business_id")
        cfg = self._resolve_cfg(config, context, node_results)
        query: Dict[str, Any] = {
            "take": max(1, min(int(cfg.get("take", 20) or 20), 500)),
            "skip": max(0, int(cfg.get("skip", 0) or 0)),
            "search": cfg.get("search"),
            "sort_by": cfg.get("sort_by"),
            "sort_desc": cfg.get("sort_desc", True),
            "include_inventory": bool(cfg.get("include_inventory", False)),
        }
        if cfg.get("category_id") is not None:
            query["category_ids"] = [_to_int(cfg.get("category_id"))]
        it = cfg.get("item_type")
        if it:
            # فیلتر استاندارد لیست کالا (مشابه API)
            query["filters"] = [
                {"property": "item_type", "operator": "=", "value": str(it)},
            ]
        return {"success": True, "data": list_products(db, int(business_id), query)}

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "لیست کالا و خدمات",
            "description": "جستجو و صفحه‌بندی محصولات",
            "config_schema": {
                "search": {"type": "string", "description": "جستجو", "required": False},
                "take": {"type": "integer", "default": 20, "required": False},
                "skip": {"type": "integer", "default": 0, "required": False},
                "category_id": {"type": "integer", "description": "دسته (اختیاری)", "required": False},
                "item_type": {"type": "string", "enum": ["product", "service"], "required": False},
                "include_inventory": {"type": "boolean", "default": False, "required": False},
            },
        }


class QueryProductAction(BaseHesabixQueryAction):
    @log_action_execution
    def execute(self, context, config, node_results):
        from app.services.product_service import get_product

        db = context.get("db")
        business_id = context.get("business_id")
        cfg = self._resolve_cfg(config, context, node_results)
        pid = _to_int(cfg.get("product_id"))
        if pid is None:
            return {"success": False, "error": "product_id is required"}
        data = get_product(db, pid, int(business_id))
        if not data:
            return {"success": False, "error": "PRODUCT_NOT_FOUND", "product_id": pid}
        return {"success": True, "data": data}

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "جزئیات کالا/خدمت",
            "config_schema": {
                "product_id": {"type": "integer", "description": "شناسه کالا", "required": True},
            },
        }


class QueryDocumentsAction(BaseHesabixQueryAction):
    @log_action_execution
    def execute(self, context, config, node_results):
        from app.services.document_service import list_documents

        db = context.get("db")
        business_id = context.get("business_id")
        cfg = self._resolve_cfg(config, context, node_results)
        q: Dict[str, Any] = {
            "take": max(1, min(int(cfg.get("take", 50) or 50), 500)),
            "skip": max(0, int(cfg.get("skip", 0) or 0)),
            "sort_desc": cfg.get("sort_desc", True),
        }
        for key in (
            "search", "document_type", "from_date", "to_date", "sort_by", "is_proforma",
        ):
            if cfg.get(key) is not None:
                q[key] = cfg.get(key)
        fy = _to_int(cfg.get("fiscal_year_id"))
        if fy is not None:
            q["fiscal_year_id"] = fy
        cur = _to_int(cfg.get("currency_id"))
        if cur is not None:
            q["currency_id"] = cur
        return {"success": True, "data": list_documents(db, int(business_id), q)}

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "لیست اسناد حسابداری",
            "description": "فیلتر و صفحه‌بندی اسناد (غیرفاکتور و ...) ",
            "config_schema": {
                "document_type": {"type": "string", "description": "نوع سند (expense, income, manual, ...)", "required": False},
                "fiscal_year_id": {"type": "integer", "required": False, "ui_type": "fiscal_year_selector", "ui_config": {"business_scoped": True}},
                "from_date": {"type": "string", "description": "از تاریخ (ISO)", "required": False},
                "to_date": {"type": "string", "description": "تا تاریخ (ISO)", "required": False},
                "search": {"type": "string", "required": False},
                "take": {"type": "integer", "default": 50, "required": False},
                "skip": {"type": "integer", "default": 0, "required": False},
            },
        }


class QueryDocumentAction(BaseHesabixQueryAction):
    @log_action_execution
    def execute(self, context, config, node_results):
        from app.services.document_service import get_document
        from adapters.db.models.document import Document

        db: Session = context.get("db")
        cfg = self._resolve_cfg(config, context, node_results)
        did = _to_int(cfg.get("document_id"))
        if did is None:
            return {"success": False, "error": "document_id is required"}
        doc = db.query(Document).filter(Document.id == did).first()
        if not doc or int(doc.business_id) != int(context.get("business_id")):
            return {"success": False, "error": "DOCUMENT_NOT_FOUND", "document_id": did}
        data = get_document(db, did)
        return {"success": True, "data": data}

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "جزئیات سند",
            "config_schema": {
                "document_id": {"type": "integer", "description": "شناسه سند", "required": True},
            },
        }


class QueryInvoicesAction(BaseHesabixQueryAction):
    @log_action_execution
    def execute(self, context, config, node_results):
        db = context.get("db")
        business_id = context.get("business_id")
        cfg = self._resolve_cfg(config, context, node_results)
        return {"success": True, "data": _list_invoices_workflow(db, int(business_id), cfg)}

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "لیست فاکتورها",
            "description": "جستجوی فاکتورها (همه انواع پشتیبانی‌شده)",
            "config_schema": {
                "document_type": {
                    "type": "string",
                    "description": "نوع فاکتور",
                    "required": False,
                    "enum": [
                        "invoice_sales", "invoice_sales_return", "invoice_purchase",
                        "invoice_purchase_return", "invoice_direct_consumption", "invoice_production", "invoice_waste",
                    ],
                },
                "search": {"type": "string", "required": False},
                "from_date": {"type": "string", "required": False},
                "to_date": {"type": "string", "required": False},
                "person_id": {"type": "integer", "description": "فیلتر طرف سند", "required": False, "ui_type": "person_selector", "ui_config": {"business_scoped": True}},
                "currency_id": {"type": "integer", "required": False, "ui_type": "currency_selector", "ui_config": {"business_scoped": True}},
                "fiscal_year_id": {"type": "integer", "required": False, "ui_type": "fiscal_year_selector", "ui_config": {"business_scoped": True}},
                "is_proforma": {"type": "boolean", "required": False},
                "take": {"type": "integer", "default": 20, "required": False},
                "skip": {"type": "integer", "default": 0, "required": False},
                "sort_by": {"type": "string", "default": "document_date", "required": False},
                "sort_desc": {"type": "boolean", "default": True, "required": False},
            },
        }


class QueryReceiptsPaymentsAction(BaseHesabixQueryAction):
    @log_action_execution
    def execute(self, context, config, node_results):
        from app.services.receipt_payment_service import list_receipts_payments

        db = context.get("db")
        business_id = context.get("business_id")
        cfg = self._resolve_cfg(config, context, node_results)
        q: Dict[str, Any] = {
            "take": max(1, min(int(cfg.get("take", 50) or 50), 500)),
            "skip": max(0, int(cfg.get("skip", 0) or 0)),
        }
        doc_type = cfg.get("type") or cfg.get("document_type")
        if doc_type:
            q["document_type"] = doc_type
        for key in ("from_date", "to_date", "account_type"):
            if cfg.get(key) is not None:
                q[key] = cfg.get(key)
        fp = _to_int(cfg.get("fiscal_year_id"))
        if fp is not None:
            q["fiscal_year_id"] = fp
        pp = _to_int(cfg.get("person_id"))
        if pp is not None:
            q["person_id"] = pp
        return {"success": True, "data": list_receipts_payments(db, int(business_id), q)}

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "لیست دریافت و پرداخت",
            "config_schema": {
                "type": {"type": "string", "description": "receipt / payment", "enum": ["receipt", "payment"], "required": False},
                "from_date": {"type": "string", "required": False},
                "to_date": {"type": "string", "required": False},
                "person_id": {"type": "integer", "required": False, "ui_type": "person_selector", "ui_config": {"business_scoped": True}},
                "account_type": {"type": "string", "enum": ["bank", "cash", "petty_cash"], "required": False},
                "fiscal_year_id": {"type": "integer", "required": False, "ui_type": "fiscal_year_selector", "ui_config": {"business_scoped": True}},
                "take": {"type": "integer", "default": 50, "required": False},
                "skip": {"type": "integer", "default": 0, "required": False},
            },
        }


class QueryWarehouseDocumentsAction(BaseHesabixQueryAction):
    @log_action_execution
    def execute(self, context, config, node_results):
        db = context.get("db")
        business_id = context.get("business_id")
        cfg = self._resolve_cfg(config, context, node_results)
        body = {
            "take": int(cfg.get("take", 20) or 20),
            "skip": int(cfg.get("skip", 0) or 0),
            "doc_type": cfg.get("doc_type"),
            "status": cfg.get("status"),
            "from_date": cfg.get("from_date"),
            "to_date": cfg.get("to_date"),
            "warehouse_id": cfg.get("warehouse_id"),
            "warehouse_ids": cfg.get("warehouse_ids"),
            "search": cfg.get("search"),
            "sort_by": cfg.get("sort_by"),
            "sort_desc": cfg.get("sort_desc", True),
            "source_document_id": _to_int(cfg.get("source_document_id")),
            "source_type": cfg.get("source_type"),
        }
        return {
            "success": True,
            "data": _search_warehouse_documents_internal(db, int(business_id), {k: v for k, v in body.items() if v is not None}),
        }

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "لیست حواله انبار",
            "description": "جستجو و فیلتر حواله‌های انبار",
            "config_schema": {
                "doc_type": {"type": "string", "description": "نوع حواله (مثلاً issue/receipt/transfer...)", "required": False},
                "status": {"type": "string", "required": False},
                "from_date": {"type": "string", "required": False},
                "to_date": {"type": "string", "required": False},
                "warehouse_id": {"type": "integer", "required": False, "ui_type": "warehouse_selector", "ui_config": {"business_scoped": True}},
                "search": {"type": "string", "description": "جستجو در کد حواله", "required": False},
                "source_document_id": {"type": "integer", "required": False},
                "take": {"type": "integer", "default": 20, "required": False},
                "skip": {"type": "integer", "default": 0, "required": False},
            },
        }
