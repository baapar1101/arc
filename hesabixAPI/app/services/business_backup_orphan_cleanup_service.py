"""
پاک‌سازی کسب‌وکارهای نیمه‌مانده از import/restore بکاپ ناموفق (قبل از اتمی شدن import).

معیار کاندید (قابل تنظیم):
- در business_backup_import_logs به‌عنوان import موفق ثبت نشده
- نام حاوی الگوی بازیابی (پیش‌فرض: «بازیابی شده») و/یا داده tenant بسیار کم
- حداقل سن (ساعت) برای جلوگیری از حذف job در حال اجرا
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Set

from sqlalchemy import inspect, text
from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.business_backup_import_log import BusinessBackupImportLog
from adapters.db.models.document import Document
from adapters.db.models.person import Person
from adapters.db.models.product import Product
from app.services.business_backup_financial_policy import (
    BACKUP_EXCLUDED_TABLES,
    is_backup_excluded_table,
    purge_excluded_financial_data,
)

logger = logging.getLogger(__name__)

DEFAULT_NAME_SUBSTRING = "بازیابی شده"
RESTORE_NAME_SUFFIX = "(بازیابی شده)"


def _to_int(value: Any) -> Optional[int]:
    if value is None:
        return None
    try:
        v = int(str(value).strip())
        return v if v > 0 else None
    except (TypeError, ValueError):
        return None


def _to_bool(value: Any, default: bool) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    s = str(value).strip().lower()
    if s in ("0", "false", "no", "off"):
        return False
    if s in ("1", "true", "yes", "on"):
        return True
    return default


def _successful_import_business_ids(db: Session) -> Set[int]:
    rows = db.query(BusinessBackupImportLog.target_business_id).distinct().all()
    return {int(r[0]) for r in rows if r[0] is not None}


def _tenant_row_counts(db: Session, business_id: int) -> Dict[str, int]:
    bid = int(business_id)
    return {
        "documents": db.query(Document).filter(Document.business_id == bid).count(),
        "persons": db.query(Person).filter(Person.business_id == bid).count(),
        "products": db.query(Product).filter(Product.business_id == bid).count(),
    }


def _name_matches_backup_import(name: str, name_substring: str) -> bool:
    n = (name or "").strip()
    if name_substring and name_substring in n:
        return True
    if RESTORE_NAME_SUFFIX in n:
        return True
    return False


def find_orphan_backup_business_candidates(
    db: Session,
    params: Dict[str, Any],
) -> List[Dict[str, Any]]:
    business_id = _to_int(params.get("business_id"))
    owner_id = _to_int(params.get("owner_id"))
    min_age_hours = _to_int(params.get("min_age_hours")) or 1
    max_documents = _to_int(params.get("max_documents"))
    if max_documents is None:
        max_documents = 0
    max_persons = _to_int(params.get("max_persons"))
    if max_persons is None:
        max_persons = 0
    max_products = _to_int(params.get("max_products"))
    if max_products is None:
        max_products = 0
    require_not_in_import_log = _to_bool(params.get("require_not_in_import_log"), True)
    require_backup_name_marker = _to_bool(params.get("require_backup_name_marker"), True)
    include_empty_shell = _to_bool(params.get("include_empty_shell"), True)
    name_substring = str(params.get("name_substring") or DEFAULT_NAME_SUBSTRING).strip()

    cutoff = datetime.utcnow() - timedelta(hours=min_age_hours)
    successful_ids = _successful_import_business_ids(db) if require_not_in_import_log else set()

    q = db.query(Business).filter(Business.deleted_at.is_(None))
    if business_id is not None:
        q = q.filter(Business.id == business_id)
    if owner_id is not None:
        q = q.filter(Business.owner_id == owner_id)

    candidates: List[Dict[str, Any]] = []
    for biz in q.order_by(Business.id.asc()).all():
        if require_not_in_import_log and int(biz.id) in successful_ids:
            continue
        created = biz.created_at or datetime.utcnow()
        if created > cutoff:
            continue

        counts = _tenant_row_counts(db, biz.id)
        name_ok = _name_matches_backup_import(biz.name, name_substring)
        empty_shell = (
            counts["documents"] <= max_documents
            and counts["persons"] <= max_persons
            and counts["products"] <= max_products
        )

        reasons: List[str] = []
        if require_not_in_import_log:
            reasons.append("not_in_successful_import_log")
        if name_ok:
            reasons.append("backup_name_marker")
        if include_empty_shell and empty_shell:
            reasons.append("low_tenant_data")

        if require_backup_name_marker and not name_ok and not (include_empty_shell and empty_shell):
            continue
        if not reasons:
            continue

        candidates.append(
            {
                "business_id": int(biz.id),
                "name": biz.name,
                "owner_id": int(biz.owner_id),
                "created_at": created.isoformat() if created else None,
                "tenant_counts": counts,
                "reasons": reasons,
            }
        )
    return candidates


def _discover_scoped_table_names(db: Session) -> List[str]:
    from adapters.api.v1.business_backups import _discover_scoped_tables

    return list(_discover_scoped_tables(db).keys())


def _tables_delete_order(db: Session, table_names: List[str]) -> List[str]:
    from adapters.api.v1.business_backups import _sort_tables_for_insert_by_fks

    ordered = _sort_tables_for_insert_by_fks(db.get_bind(), table_names)
    without_businesses = [t for t in ordered if t != "businesses"]
    return list(reversed(without_businesses))


def _try_replica_role(conn) -> bool:
    from adapters.api.v1.business_backups import _try_set_session_replication_role_replica

    return _try_set_session_replication_role_replica(conn)


def _reset_replica_role(conn, had: bool) -> None:
    from adapters.api.v1.business_backups import _reset_session_replication_role

    _reset_session_replication_role(conn, had)


def hard_delete_business_tenant_data(db: Session, business_id: int) -> Dict[str, Any]:
    """
    حذف سخت داده‌های tenant و ردیف businesses.
    برخلاف soft-delete کاربر، برای زباله‌های import نیمه‌کاره است.
    """
    bid = int(business_id)
    biz = db.query(Business).filter(Business.id == bid, Business.deleted_at.is_(None)).first()
    if not biz:
        return {"deleted": False, "reason": "business_not_found_or_already_deleted"}

    conn = db.connection()
    replica_ok = _try_replica_role(conn)
    tables_deleted: Dict[str, int] = {}

    try:
        purge_excluded_financial_data(db, bid)

        scoped = _discover_scoped_table_names(db)
        for t in sorted(BACKUP_EXCLUDED_TABLES):
            if t not in scoped:
                scoped.append(t)

        for table in _tables_delete_order(db, scoped):
            if table == "businesses":
                continue
            try:
                inspector = inspect(db.get_bind())
                cols = {c["name"] for c in inspector.get_columns(table)}
            except Exception:
                continue
            if "business_id" not in cols:
                continue
            result = conn.execute(
                text(f'DELETE FROM "{table}" WHERE business_id = :bid'),
                {"bid": bid},
            )
            tables_deleted[table] = int(result.rowcount or 0)

        for extra in ("business_permissions", "business_currencies", "fiscal_years"):
            try:
                result = conn.execute(
                    text(f'DELETE FROM "{extra}" WHERE business_id = :bid'),
                    {"bid": bid},
                )
                tables_deleted[extra] = int(result.rowcount or 0)
            except Exception:
                pass

        db.query(BusinessBackupImportLog).filter(
            BusinessBackupImportLog.target_business_id == bid
        ).delete(synchronize_session=False)

        conn.execute(text('DELETE FROM "businesses" WHERE id = :bid'), {"bid": bid})
        tables_deleted["businesses"] = 1
    finally:
        _reset_replica_role(conn, replica_ok)

    return {"deleted": True, "business_id": bid, "tables_deleted": tables_deleted}


def run_orphan_backup_business_cleanup(
    db: Session,
    params: Dict[str, Any],
    *,
    dry_run: bool,
    log_fn: Optional[Any] = None,
) -> Dict[str, Any]:
    """اجرای پاک‌سازی؛ log_fn(run_id, level, message) اختیاری برای admin script."""
    def _log(level: str, msg: str) -> None:
        if log_fn:
            log_fn(level, msg)
        else:
            getattr(logger, level if level in ("info", "warning", "error") else "info")(msg)

    candidates = find_orphan_backup_business_candidates(db, params)
    limit = _to_int(params.get("limit"))
    if limit is not None:
        candidates = candidates[:limit]

    stats: Dict[str, Any] = {
        "scanned": len(candidates),
        "candidates": candidates,
        "deleted_count": 0,
        "deleted_business_ids": [],
        "dry_run": dry_run,
        "errors": 0,
        "error_details": [],
    }
    _log("info", f"کاندیدهای یافت‌شده: {len(candidates)} (dry_run={dry_run})")

    for item in candidates:
        bid = item["business_id"]
        if dry_run:
            stats["deleted_count"] += 1
            stats["deleted_business_ids"].append(bid)
            _log("info", f"[dry_run] حذف می‌شد: business_id={bid} name={item.get('name')}")
            continue
        try:
            result = hard_delete_business_tenant_data(db, bid)
            if result.get("deleted"):
                stats["deleted_count"] += 1
                stats["deleted_business_ids"].append(bid)
                _log("info", f"حذف شد: business_id={bid} tables={result.get('tables_deleted')}")
            else:
                stats["errors"] += 1
                stats["error_details"].append({"business_id": bid, "error": result.get("reason")})
        except Exception as exc:
            stats["errors"] += 1
            stats["error_details"].append({"business_id": bid, "error": str(exc)})
            _log("error", f"خطا در حذف business_id={bid}: {exc}")
            try:
                db.rollback()
            except Exception:
                pass

    stats["updated_lines"] = stats["deleted_count"]
    return stats
