"""
Queryهای فاز ۲ AI — پروژه، مالیات، workflow، BOM، تعمیرگاه، توزیع، گارانتی.
"""
from __future__ import annotations

import json
import logging
from typing import Any, Dict, List, Optional

from sqlalchemy import and_, func, or_, select
from sqlalchemy.orm import Session

from app.core.auth_dependency import AuthContext
from app.services.ai.ai_query_service import _build_list_query, _clamp_pagination, _to_int

logger = logging.getLogger(__name__)

PHASE2_ENTITIES = frozenset({
    "project",
    "bom",
    "repair_order",
    "tax_workspace",
    "workflow",
    "workflow_execution",
    "warranty_code",
    "petty_cash",
    "distribution_route",
    "production_document",
})

PHASE2_ENTITY_PERMISSIONS: Dict[str, List[str]] = {
    "project": ["accounting_documents.view"],
    "bom": ["inventory.read"],
    "repair_order": ["invoices.read"],
    "tax_workspace": ["moadian.view", "invoices.read"],
    "workflow": ["workflows.view"],
    "workflow_execution": ["workflows.view"],
    "warranty_code": ["warranty.read"],
    "petty_cash": ["petty_cash.view"],
    "distribution_route": ["distribution.view"],
    "production_document": ["invoices.read"],
}


def _format_project_row(project: Any) -> Dict[str, Any]:
    return {
        "id": project.id,
        "code": project.code,
        "name": project.name,
        "description": project.description,
        "status": project.status,
        "is_active": project.is_active,
        "start_date": project.start_date.isoformat() if project.start_date else None,
        "end_date": project.end_date.isoformat() if project.end_date else None,
        "budget": float(project.budget) if project.budget is not None else None,
        "currency_id": project.currency_id,
        "manager_user_id": project.manager_user_id,
        "person_id": project.person_id,
    }


def search_projects(db: Session, business_id: int, filters: Dict[str, Any]) -> Dict[str, Any]:
    from adapters.db.repositories.project_repository import ProjectRepository

    q = _clamp_pagination(filters, default_take=50)
    page = max(1, _to_int(filters.get("page"), 1) or 1)
    limit = q["take"]
    skip = q["skip"] if filters.get("skip") is not None else (page - 1) * limit

    repo = ProjectRepository(db)
    flt: Dict[str, Any] = {}
    if filters.get("status"):
        flt["status"] = filters["status"]
    if filters.get("is_active") is not None:
        flt["is_active"] = filters["is_active"]
    if filters.get("person_id"):
        flt["person_id"] = filters["person_id"]
    if filters.get("manager_user_id"):
        flt["manager_user_id"] = filters["manager_user_id"]

    projects, total = repo.search(
        business_id=business_id,
        search_term=filters.get("search"),
        filters=flt or None,
        skip=skip,
        limit=limit,
    )
    return {
        "items": [_format_project_row(p) for p in projects],
        "pagination": {
            "total": total,
            "page": (skip // max(1, limit)) + 1,
            "per_page": limit,
            "has_next": skip + limit < total,
            "has_prev": skip > 0,
        },
    }


def get_project_summary(db: Session, business_id: int, project_id: int) -> Dict[str, Any]:
    from adapters.db.repositories.project_repository import ProjectRepository
    from app.services.project_service import get_project_statistics

    repo = ProjectRepository(db)
    project = repo.get_by_id(project_id, load_relations=True)
    if not project or project.business_id != business_id:
        raise ValueError(f"پروژه {project_id} یافت نشد")
    stats = get_project_statistics(db, project_id)
    return {"project": _format_project_row(project), "statistics": stats}


def search_tax_workspace(
    db: Session,
    business_id: int,
    filters: Dict[str, Any],
) -> Dict[str, Any]:
    """فاکتورهای علامت‌خورده در کارپوشه مودیان."""
    from adapters.db.models.document import Document
    from app.services.invoice_service import SUPPORTED_INVOICE_TYPES, invoice_document_to_dict

    q = _clamp_pagination(filters, default_take=50, max_take=100)
    skip, take = q["skip"], q["take"]

    stmt = db.query(Document).filter(
        Document.business_id == business_id,
        Document.document_type.in_(list(SUPPORTED_INVOICE_TYPES)),
    )
    if filters.get("document_type"):
        stmt = stmt.filter(Document.document_type == filters["document_type"])
    if filters.get("fiscal_year_id"):
        stmt = stmt.filter(Document.fiscal_year_id == int(filters["fiscal_year_id"]))
    search = (filters.get("search") or "").strip()
    if search:
        pat = f"%{search}%"
        stmt = stmt.filter(
            or_(Document.code.ilike(pat), Document.description.ilike(pat))
        )

    stmt = stmt.order_by(Document.document_date.desc(), Document.id.desc())
    candidates = stmt.limit(800).all()

    items: List[Dict[str, Any]] = []
    for doc in candidates:
        extra = doc.extra_info or {}
        if isinstance(extra, str):
            try:
                extra = json.loads(extra)
            except json.JSONDecodeError:
                extra = {}
        if not extra.get("tax_workspace"):
            continue
        tax_status = extra.get("tax_status") or extra.get("moadian_status")
        if filters.get("tax_status") and tax_status != filters.get("tax_status"):
            continue
        try:
            items.append(invoice_document_to_dict(db, doc))
        except Exception as exc:
            logger.warning("tax_workspace invoice_to_dict id=%s: %s", doc.id, exc)
            items.append(
                {
                    "id": doc.id,
                    "code": doc.code,
                    "document_type": doc.document_type,
                    "tax_status": tax_status,
                }
            )

    total = len(items)
    page_items = items[skip : skip + take]
    return {
        "items": page_items,
        "pagination": {
            "total": total,
            "page": (skip // max(1, take)) + 1,
            "per_page": take,
            "has_next": skip + take < total,
            "has_prev": skip > 0,
        },
    }


def get_tax_settings_for_ai(db: Session, business_id: int) -> Dict[str, Any]:
    from app.services.tax_setting_service import get_tax_setting, serialize_tax_setting

    setting = get_tax_setting(db, business_id)
    data = serialize_tax_setting(setting, business_id, db=db)
    data.pop("private_key", None)
    data.pop("certificate", None)
    if data.get("public_key"):
        data["has_public_key"] = True
        data.pop("public_key", None)
    return data


def get_tax_data_quality_for_ai(db: Session, business_id: int) -> Dict[str, Any]:
    from app.services.tax_data_quality_service import get_tax_data_quality

    report = get_tax_data_quality(db, business_id)
    return {
        "business_id": report.business_id,
        "product_missing_tax_code": report.product_missing_tax_code,
        "product_missing_tax_unit": report.product_missing_tax_unit,
        "product_samples": report.product_samples,
        "person_missing_national_id": report.person_missing_national_id,
        "person_missing_economic_id": report.person_missing_economic_id,
        "person_samples": report.person_samples,
    }


def list_workflows_for_ai(db: Session, business_id: int, filters: Dict[str, Any]) -> Dict[str, Any]:
    from adapters.db.models.workflow import Workflow

    q = _clamp_pagination(filters, default_take=20, max_take=100)
    stmt = select(Workflow).where(Workflow.business_id == business_id)
    if filters.get("status"):
        stmt = stmt.where(Workflow.status == filters["status"])
    if filters.get("search"):
        stmt = stmt.where(Workflow.name.ilike(f"%{filters['search']}%"))
    stmt = stmt.order_by(Workflow.created_at.desc())

    total = db.execute(stmt.with_only_columns(func.count()).order_by(None)).scalar_one() or 0
    rows = list(
        db.execute(stmt.offset(q["skip"]).limit(q["take"])).scalars().all()
    )
    items = [
        {
            "id": w.id,
            "name": w.name,
            "description": w.description,
            "status": w.status.value if hasattr(w.status, "value") else w.status,
            "created_at": w.created_at.isoformat() if w.created_at else None,
            "updated_at": w.updated_at.isoformat() if w.updated_at else None,
        }
        for w in rows
    ]
    return {
        "items": items,
        "pagination": {
            "total": total,
            "page": (q["skip"] // max(1, q["take"])) + 1,
            "per_page": q["take"],
            "has_next": q["skip"] + q["take"] < total,
            "has_prev": q["skip"] > 0,
        },
    }


def list_workflow_executions_for_ai(
    db: Session,
    business_id: int,
    workflow_id: int,
    filters: Dict[str, Any],
) -> Dict[str, Any]:
    from adapters.db.models.workflow import Workflow, WorkflowExecution

    workflow = db.get(Workflow, workflow_id)
    if not workflow or workflow.business_id != business_id:
        raise ValueError(f"Workflow {workflow_id} یافت نشد")

    q = _clamp_pagination(filters, default_take=20, max_take=100)
    base = select(WorkflowExecution).where(WorkflowExecution.workflow_id == workflow_id)
    total = db.execute(
        base.with_only_columns(func.count()).order_by(None)
    ).scalar_one() or 0
    rows = list(
        db.execute(
            base.order_by(WorkflowExecution.created_at.desc())
            .offset(q["skip"])
            .limit(q["take"])
        ).scalars().all()
    )
    items = [
        {
            "id": e.id,
            "workflow_id": e.workflow_id,
            "status": e.status.value if hasattr(e.status, "value") else e.status,
            "started_at": e.started_at.isoformat() if e.started_at else None,
            "completed_at": e.completed_at.isoformat() if e.completed_at else None,
            "error_message": e.error_message,
        }
        for e in rows
    ]
    return {
        "items": items,
        "workflow_id": workflow_id,
        "pagination": {
            "total": total,
            "page": (q["skip"] // max(1, q["take"])) + 1,
            "per_page": q["take"],
        },
    }


def phase2_entity_search(
    db: Session,
    business_id: int,
    entity: str,
    filters: Dict[str, Any],
    user_context: Optional[AuthContext] = None,
) -> Any:
    if entity == "project":
        return search_projects(db, business_id, filters)
    if entity == "bom":
        from app.services.bom_service import list_boms

        product_id = _to_int(filters.get("product_id"))
        return list_boms(db, business_id, product_id)
    if entity == "repair_order":
        from app.services.repair_shop_service import list_repair_orders

        q = _clamp_pagination(filters, default_take=50)
        flt: Dict[str, Any] = {}
        for key in ("status", "customer_person_id", "assigned_technician_id", "search"):
            if filters.get(key) is not None:
                flt[key] = filters[key]
        return list_repair_orders(
            db, business_id, flt, offset=q["skip"], limit=q["take"]
        )
    if entity == "tax_workspace":
        return search_tax_workspace(db, business_id, filters)
    if entity == "workflow":
        return list_workflows_for_ai(db, business_id, filters)
    if entity == "workflow_execution":
        wid = _to_int(filters.get("workflow_id"))
        if wid is None:
            raise ValueError("workflow_id در filters الزامی است")
        return list_workflow_executions_for_ai(db, business_id, wid, filters)
    if entity == "warranty_code":
        from app.services.warranty_service import list_warranty_codes

        q = _clamp_pagination(filters, default_take=50)
        return list_warranty_codes(
            db,
            business_id,
            status=filters.get("status"),
            product_id=_to_int(filters.get("product_id")),
            limit=q["take"],
            skip=q["skip"],
        )
    if entity == "petty_cash":
        from app.services.petty_cash_service import list_petty_cash

        q = _build_list_query(filters)
        if q.get("search") and not q.get("search_fields"):
            q["search_fields"] = ["code", "name"]
        return list_petty_cash(db, business_id, q)
    if entity == "distribution_route":
        from app.services.distribution_service import list_routes

        if user_context is None:
            raise ValueError("user_context برای distribution_route لازم است")
        routes = list_routes(db, business_id, user_context)
        return {"items": routes, "total": len(routes)}
    if entity == "production_document":
        from app.services.document_service import list_documents

        q = _build_list_query(filters)
        q["document_type"] = q.get("document_type") or "invoice_production"
        return list_documents(db, business_id, q)
    raise ValueError(f"entity فاز۲ ناشناخته: {entity}")


def phase2_entity_get(
    db: Session,
    business_id: int,
    entity: str,
    record_id: Optional[int],
    filters: Dict[str, Any],
    user_context: Optional[AuthContext] = None,
) -> Any:
    if entity == "project":
        pid = record_id or _to_int(filters.get("project_id"))
        if pid is None:
            raise ValueError("project_id الزامی است")
        return get_project_summary(db, business_id, pid)
    if entity == "bom":
        from app.services.bom_service import get_bom

        bid = record_id or _to_int(filters.get("bom_id"))
        if bid is None:
            raise ValueError("bom_id الزامی است")
        data = get_bom(db, business_id, bid)
        if not data:
            raise ValueError(f"BOM {bid} یافت نشد")
        return data
    if entity == "repair_order":
        from app.services.repair_shop_service import get_repair_order

        oid = record_id or _to_int(filters.get("repair_order_id"))
        if oid is None:
            raise ValueError("repair_order_id الزامی است")
        return get_repair_order(db, business_id, oid)
    if entity == "workflow":
        from adapters.db.models.workflow import Workflow

        wid = record_id or _to_int(filters.get("workflow_id"))
        if wid is None:
            raise ValueError("workflow_id الزامی است")
        w = db.get(Workflow, wid)
        if not w or w.business_id != business_id:
            raise ValueError(f"Workflow {wid} یافت نشد")
        return {
            "id": w.id,
            "name": w.name,
            "description": w.description,
            "status": w.status.value if hasattr(w.status, "value") else w.status,
            "created_at": w.created_at.isoformat() if w.created_at else None,
        }
    raise ValueError(f"get برای entity «{entity}» در فاز۲ پشتیبانی نمی‌شود")
