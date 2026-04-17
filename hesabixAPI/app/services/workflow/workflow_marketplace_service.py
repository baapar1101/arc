"""
مخزن ورک‌فلو: sanitize برای انتشار و remap شناسه‌ها هنگام نصب در کسب‌وکار دیگر.
"""

from __future__ import annotations

import copy
import logging
import re
import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

import sqlalchemy as sa
from sqlalchemy import func, or_, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.user import User
from adapters.db.models.workflow import Workflow, WorkflowStatus
from adapters.db.models.workflow_marketplace import (
    WorkflowMarketplaceInstall,
    WorkflowMarketplacePackage,
    WorkflowMarketplacePackageStatus,
)

_logger = logging.getLogger(__name__)

# کلیدهایی که نباید در بستهٔ عمومی بمانند (ارجاع به موجودیت‌های محیطی یا اسرار)
_ENTITY_REF_KEYS = frozenset(
    {
        "business_id",
        "user_id",
        "person_id",
        "person_ids",
        "customer_id",
        "supplier_id",
        "product_id",
        "warehouse_id",
        "account_id",
        "bank_account_id",
        "cash_register_id",
        "petty_cash_id",
        "invoice_id",
        "document_id",
        "price_list_id",
        "created_by_user_id",
    }
)


def _sensitive_key(name: str) -> bool:
    nl = name.lower()
    if nl in _ENTITY_REF_KEYS:
        return True
    for frag in ("secret", "password", "token", "api_key", "authorization", "bearer", "webhook_secret"):
        if frag in nl:
            return True
    return False


def _sanitize_value(obj: Any) -> Any:
    if isinstance(obj, dict):
        out: Dict[str, Any] = {}
        for k, v in obj.items():
            if _sensitive_key(str(k)):
                continue
            out[k] = _sanitize_value(v)
        return out
    if isinstance(obj, list):
        return [_sanitize_value(x) for x in obj]
    return obj


def sanitize_workflow_for_marketplace(
    workflow_data: Dict[str, Any],
    settings: Optional[Dict[str, Any]],
) -> Tuple[Dict[str, Any], Optional[Dict[str, Any]]]:
    """کپی عمیق، حذف یادداشت نودها و مقادیر حساس/ارجاعی."""
    data = copy.deepcopy(workflow_data or {})
    nodes = data.get("nodes") or []
    if isinstance(nodes, list):
        cleaned_nodes: List[Any] = []
        for n in nodes:
            if not isinstance(n, dict):
                cleaned_nodes.append(n)
                continue
            nn = dict(n)
            nn.pop("comment", None)
            cfg = nn.get("config")
            if isinstance(cfg, dict):
                nn["config"] = _sanitize_value(cfg)
            cleaned_nodes.append(nn)
        data["nodes"] = cleaned_nodes
    conns = data.get("connections")
    if isinstance(conns, list):
        data["connections"] = [_sanitize_value(c) if isinstance(c, dict) else c for c in conns]

    st: Optional[Dict[str, Any]] = None
    if settings:
        st = _sanitize_value(dict(settings))
        st.pop("webhook_secret", None)

    return data, st


def _rewrite_dollar_refs_in_string(s: str, id_map: Dict[str, str]) -> str:
    if "$" not in s or not id_map:
        return s
    out = s
    for old, new in sorted(id_map.items(), key=lambda x: -len(x[0])):
        e = re.escape(old)
        out = re.sub(
            r"\$" + e + r"(\.[A-Za-z0-9_]+)?",
            lambda m, n=new: f"${n}{m.group(1) or ''}",
            out,
        )
    return out


def _rewrite_refs_deep(obj: Any, id_map: Dict[str, str]) -> Any:
    if isinstance(obj, str):
        return _rewrite_dollar_refs_in_string(obj, id_map)
    if isinstance(obj, dict):
        return {k: _rewrite_refs_deep(v, id_map) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_rewrite_refs_deep(x, id_map) for x in obj]
    return obj


def remap_workflow_ids_for_import(workflow_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    شناسهٔ جدید برای هر نود و به‌روزرسانی connections و ارجاعات $ در رشته‌ها.
    """
    data = copy.deepcopy(workflow_data or {})
    nodes = data.get("nodes") or []
    id_map: Dict[str, str] = {}
    new_nodes: List[Dict[str, Any]] = []
    for n in nodes:
        if not isinstance(n, dict):
            continue
        old_id = n.get("id")
        new_id = str(uuid.uuid4())
        if old_id is not None and str(old_id):
            id_map[str(old_id)] = new_id
        nn = dict(n)
        nn["id"] = new_id
        new_nodes.append(nn)
    data["nodes"] = new_nodes

    conns = data.get("connections") or []
    new_conns: List[Dict[str, Any]] = []
    if isinstance(conns, list):
        for c in conns:
            if not isinstance(c, dict):
                continue
            nc = dict(c)
            s, t = c.get("source"), c.get("target")
            if s is not None and str(s) in id_map:
                nc["source"] = id_map[str(s)]
            if t is not None and str(t) in id_map:
                nc["target"] = id_map[str(t)]
            new_conns.append(nc)
    data["connections"] = new_conns

    if id_map:
        data = _rewrite_refs_deep(data, id_map)
    return data


def _normalize_tags(raw: Any) -> List[str]:
    if not raw:
        return []
    if not isinstance(raw, list):
        return []
    out: List[str] = []
    for t in raw[:30]:
        if isinstance(t, str):
            s = t.strip()
            if s and len(s) <= 64:
                out.append(s)
    return out[:20]


def publish_package(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    workflow_id: int,
    title: str,
    short_description: Optional[str],
    long_description: Optional[str],
    tags: Any,
    version_label: str,
    changelog: Optional[str],
) -> WorkflowMarketplacePackage:
    wf = db.get(Workflow, int(workflow_id))
    if not wf or wf.business_id != business_id:
        raise ValueError("WORKFLOW_NOT_FOUND")

    title = (title or "").strip()
    if not title or len(title) > 255:
        raise ValueError("WORKFLOW_MARKETPLACE_TITLE_INVALID")

    ver = (version_label or "1.0.0").strip()[:64]
    if not ver:
        ver = "1.0.0"

    wd, st = sanitize_workflow_for_marketplace(wf.workflow_data or {}, wf.settings if isinstance(wf.settings, dict) else None)

    from adapters.api.v1.workflows import validate_workflow_data

    val_errs = validate_workflow_data(wd)
    if val_errs:
        raise ValueError("WORKFLOW_DATA_INVALID_AFTER_SANITIZE")

    pkg = WorkflowMarketplacePackage(
        source_workflow_id=wf.id,
        publisher_user_id=user_id,
        publisher_business_id=business_id,
        title=title,
        short_description=(short_description or "").strip() or None,
        long_description=(long_description or "").strip() or None,
        tags=_normalize_tags(tags),
        workflow_data=wd,
        settings=st,
        version_label=ver,
        changelog=(changelog or "").strip() or None,
        status=WorkflowMarketplacePackageStatus.PUBLISHED.value,
        install_count=0,
        published_at=datetime.utcnow(),
    )
    db.add(pkg)
    db.commit()
    db.refresh(pkg)
    return pkg


def _publisher_display_row(db: Session, user_id: int, business_id: int) -> Tuple[Optional[str], Optional[str]]:
    u = db.get(User, user_id)
    parts = [x for x in [getattr(u, "first_name", None), getattr(u, "last_name", None)] if x]
    display = " ".join(parts).strip() if parts else None
    if not display and u and getattr(u, "email", None):
        display = str(u.email)
    b = db.get(Business, business_id)
    biz_name = getattr(b, "name", None) if b else None
    return display, biz_name


def package_to_public_dict(db: Session, pkg: WorkflowMarketplacePackage, request: Any) -> Dict[str, Any]:
    from app.core.responses import format_datetime_fields

    display, biz_name = _publisher_display_row(db, pkg.publisher_user_id, pkg.publisher_business_id)
    base = {
        "id": pkg.id,
        "title": pkg.title,
        "short_description": pkg.short_description,
        "long_description": pkg.long_description,
        "tags": pkg.tags or [],
        "version_label": pkg.version_label,
        "changelog": pkg.changelog,
        "status": pkg.status,
        "install_count": pkg.install_count,
        "publisher_user_id": pkg.publisher_user_id,
        "publisher_business_id": pkg.publisher_business_id,
        "publisher_display_name": display,
        "publisher_business_name": biz_name,
        "published_at": pkg.published_at,
        "created_at": pkg.created_at,
        "updated_at": pkg.updated_at,
    }
    return format_datetime_fields(base, request)


def package_detail_dict(db: Session, pkg: WorkflowMarketplacePackage, request: Any, include_graph: bool) -> Dict[str, Any]:
    d = package_to_public_dict(db, pkg, request)
    if include_graph:
        d["workflow_data"] = pkg.workflow_data
        d["settings"] = pkg.settings
    return d


def list_published_packages(
    db: Session,
    *,
    skip: int,
    take: int,
    search: Optional[str],
    tag: Optional[str],
) -> Tuple[List[WorkflowMarketplacePackage], int]:
    filters = [WorkflowMarketplacePackage.status == WorkflowMarketplacePackageStatus.PUBLISHED.value]
    if search and search.strip():
        q = f"%{search.strip()}%"
        filters.append(
            or_(
                WorkflowMarketplacePackage.title.ilike(q),
                WorkflowMarketplacePackage.short_description.ilike(q),
            )
        )
    if tag and tag.strip():
        filters.append(
            func.cast(WorkflowMarketplacePackage.tags, sa.String).ilike(f'%"{tag.strip()}"%')
        )
    total = db.execute(select(func.count()).select_from(WorkflowMarketplacePackage).where(*filters)).scalar_one()
    stmt = (
        select(WorkflowMarketplacePackage)
        .where(*filters)
        .order_by(
            WorkflowMarketplacePackage.published_at.desc(),
            WorkflowMarketplacePackage.id.desc(),
        )
        .offset(max(skip, 0))
        .limit(min(max(take, 1), 100))
    )
    rows = list(db.execute(stmt).scalars().all())
    return rows, int(total)


def list_my_packages(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    skip: int,
    take: int,
) -> Tuple[List[WorkflowMarketplacePackage], int]:
    filters = [
        WorkflowMarketplacePackage.publisher_business_id == business_id,
        WorkflowMarketplacePackage.publisher_user_id == user_id,
    ]
    total = db.execute(select(func.count()).select_from(WorkflowMarketplacePackage).where(*filters)).scalar_one()
    stmt = (
        select(WorkflowMarketplacePackage)
        .where(*filters)
        .order_by(WorkflowMarketplacePackage.created_at.desc())
        .offset(max(skip, 0))
        .limit(min(max(take, 1), 100))
    )
    rows = list(db.execute(stmt).scalars().all())
    return rows, int(total)


def get_published_package(db: Session, package_id: int) -> Optional[WorkflowMarketplacePackage]:
    p = db.get(WorkflowMarketplacePackage, int(package_id))
    if not p or p.status != WorkflowMarketplacePackageStatus.PUBLISHED.value:
        return None
    return p


def get_package_for_owner(db: Session, package_id: int, business_id: int, user_id: int) -> Optional[WorkflowMarketplacePackage]:
    p = db.get(WorkflowMarketplacePackage, int(package_id))
    if not p:
        return None
    if p.publisher_business_id != business_id or p.publisher_user_id != user_id:
        return None
    return p


def install_package_to_business(
    db: Session,
    *,
    package_id: int,
    target_business_id: int,
    user_id: int,
    new_name: Optional[str],
) -> Tuple[Workflow, WorkflowMarketplaceInstall]:
    _logger.debug(
        "install_package_to_business enter package_id=%s target_business_id=%s user_id=%s",
        package_id,
        target_business_id,
        user_id,
    )
    pkg = get_published_package(db, package_id)
    if not pkg:
        _logger.warning("install_package_to_business package_not_found package_id=%s", package_id)
        raise ValueError("WORKFLOW_MARKETPLACE_PACKAGE_NOT_FOUND")

    wd = remap_workflow_ids_for_import(pkg.workflow_data or {})
    from adapters.api.v1.workflows import validate_workflow_data

    val_errs = validate_workflow_data(wd)
    if val_errs:
        _logger.warning(
            "install_package_to_business validation_failed package_id=%s errors=%s",
            package_id,
            val_errs[:5],
        )
        raise ValueError("WORKFLOW_DATA_INVALID_IMPORT")

    name = (new_name or "").strip() or f"{pkg.title} ({pkg.version_label})"
    if len(name) > 255:
        name = name[:255]

    wf = Workflow(
        business_id=target_business_id,
        name=name,
        description=None,
        status=WorkflowStatus.DRAFT,
        workflow_data=wd,
        settings=None,
        created_by_user_id=user_id,
    )
    db.add(wf)
    db.flush()
    _logger.debug(
        "install_package_to_business after_flush workflow_id=%s package_id=%s",
        wf.id,
        package_id,
    )

    from app.services.workflow.workflow_trigger_service import ensure_workflow_webhook_settings

    merged = ensure_workflow_webhook_settings(wd, dict(wf.settings or {}))
    wf.settings = merged if merged else None

    inst = WorkflowMarketplaceInstall(
        package_id=pkg.id,
        business_id=target_business_id,
        installed_workflow_id=wf.id,
        installed_by_user_id=user_id,
    )
    db.add(inst)

    pkg.install_count = int(pkg.install_count or 0) + 1

    try:
        db.commit()
    except SQLAlchemyError as e:
        _logger.exception(
            "install_package_to_business commit_failed package_id=%s workflow_id=%s: %s",
            package_id,
            getattr(wf, "id", None),
            e,
        )
        db.rollback()
        raise

    db.refresh(wf)
    db.refresh(inst)
    db.refresh(pkg)
    _logger.info(
        "install_package_to_business done workflow_id=%s package_id=%s business_id=%s",
        wf.id,
        package_id,
        target_business_id,
    )
    return wf, inst
