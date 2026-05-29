"""
سیاست امنیت مالی برای بکاپ/بازیابی tenant کسب‌وکار.

جداول لیست‌شده در بکاپ export نمی‌شوند و در restore/import درج نمی‌شوند.
پس از هر بازیابی، داده‌های مالی/اعتباری باقی‌مانده (مثلاً از بکاپ‌های قدیمی) پاک می‌شوند.
"""
from __future__ import annotations

import hashlib
import logging
from datetime import datetime
from decimal import Decimal
from typing import Any, Dict, Iterable, List, Optional

from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)

# نسخه metadata بکاپ (v1.2: snapshot ستون‌ها در table_schemas برای سازگاری import)
BACKUP_SCHEMA_VERSION = "v1.2"

# جداولی که نباید در بکاپ tenant یا restore کسب‌وکار باشند
BACKUP_EXCLUDED_TABLES: frozenset[str] = frozenset({
    # کیف پول
    "wallet_accounts",
    "wallet_transactions",
    "wallet_payouts",
    "wallet_settings",
    # اشتراک و مصرف AI
    "user_ai_subscriptions",
    "ai_usage_logs",
    "ai_invoices",
    "ai_chat_sessions",
    "ai_voice_interactions",
    # ذخیره‌سازی ابری
    "business_storage_subscriptions",
    "storage_invoices",
    "storage_usage_transactions",
    # مارکت‌پلیس / پلاگین
    "business_plugins",
    "marketplace_orders",
    "marketplace_invoices",
})


def is_backup_excluded_table(table_name: str) -> bool:
    return table_name in BACKUP_EXCLUDED_TABLES


def filter_restorable_table_names(table_names: Iterable[str]) -> List[str]:
    return [t for t in table_names if not is_backup_excluded_table(t)]


def build_backup_metadata(
    *,
    business_id: int,
    table_names: Iterable[str],
    owner_id: Optional[int] = None,
    table_schemas: Optional[Dict[str, List[str]]] = None,
) -> Dict[str, Any]:
    included = filter_restorable_table_names(table_names)
    meta: Dict[str, Any] = {
        "schema_version": BACKUP_SCHEMA_VERSION,
        "created_at": datetime.utcnow().isoformat(),
        "business_id": business_id,
        "tables": included,
        "financial_data_excluded": True,
        "excluded_tables": sorted(BACKUP_EXCLUDED_TABLES),
    }
    if owner_id is not None:
        meta["owner_id"] = int(owner_id)
    if table_schemas:
        meta["table_schemas"] = table_schemas
    return meta


def resolve_backup_owner_id(
    metadata: Dict[str, Any],
    *,
    db: Optional[Session] = None,
    backup_business_row: Optional[Dict[str, Any]] = None,
) -> Optional[int]:
    """شناسه مالک را از metadata، ردیف businesses بکاپ، یا DB استخراج می‌کند."""
    owner = metadata.get("owner_id")
    if owner is not None:
        try:
            return int(owner)
        except (TypeError, ValueError):
            pass

    if backup_business_row:
        row_owner = backup_business_row.get("owner_id")
        if row_owner is not None:
            try:
                return int(row_owner)
            except (TypeError, ValueError):
                pass

    if db is not None:
        bid = metadata.get("business_id")
        if bid is not None:
            try:
                from adapters.db.models.business import Business

                biz = db.get(Business, int(bid))
                if biz is not None and getattr(biz, "owner_id", None) is not None:
                    return int(biz.owner_id)
            except (TypeError, ValueError):
                pass
    return None


def validate_backup_owner(
    metadata: Dict[str, Any],
    importing_user_id: int,
    *,
    db: Optional[Session] = None,
    backup_business_row: Optional[Dict[str, Any]] = None,
) -> None:
    """
    فقط مالک کسب‌وکار مبدأ می‌تواند بکاپ را import/restore کند.
    بکاپ v1 بدون owner_id: از businesses.jsonl یا DB؛ در غیر این صورت رد.
    """
    from app.core.responses import ApiError

    owner_id = resolve_backup_owner_id(
        metadata, db=db, backup_business_row=backup_business_row
    )
    if owner_id is None:
        raise ApiError(
            "BACKUP_LEGACY_NOT_ALLOWED",
            "این فایل پشتیبان قدیمی است و مالک آن مشخص نیست. لطفاً نسخه پشتیبان جدید (.hbx) بگیرید و دوباره تلاش کنید.",
            http_status=400,
        )
    if int(owner_id) != int(importing_user_id):
        raise ApiError(
            "BACKUP_OWNER_MISMATCH",
            "این فایل پشتیبان متعلق به کاربر دیگری است و قابل بازیابی نیست.",
            http_status=403,
        )


def compute_backup_checksum(file_bytes: bytes) -> str:
    return hashlib.sha256(file_bytes).hexdigest()


def _advisory_lock_keys(user_id: int, backup_checksum: str) -> tuple[int, int]:
    """دو کلید int32 برای pg_advisory_xact_lock."""
    digest = hashlib.sha256(f"{user_id}:{backup_checksum}".encode()).digest()
    k1 = int.from_bytes(digest[0:4], "big", signed=False) & 0x7FFFFFFF
    k2 = int.from_bytes(digest[4:8], "big", signed=False) & 0x7FFFFFFF
    return k1, k2


def acquire_backup_import_lock(db: Session, user_id: int, backup_checksum: str) -> None:
    """
    قفل تراکنشی PostgreSQL برای جلوگیری از import همزمان همان فایل.
    در صورت عدم پشتیبانی، فقط به assert/unique constraint تکیه می‌شود.
    """
    k1, k2 = _advisory_lock_keys(user_id, backup_checksum)
    try:
        db.execute(
            text("SELECT pg_advisory_xact_lock(:k1, :k2)"),
            {"k1": k1, "k2": k2},
        )
    except Exception as e:
        logger.warning(
            "pg_advisory_xact_lock unavailable user_id=%s: %s",
            user_id,
            e,
        )


def guard_new_business_import(
    db: Session,
    *,
    user_id: int,
    backup_checksum: str,
    import_mode: str,
) -> None:
    """قفل + بررسی تکرار قبل از ایجاد کسب‌وکار جدید."""
    if import_mode not in ("new_business", "legacy_api"):
        return
    acquire_backup_import_lock(db, user_id, backup_checksum)
    assert_backup_import_allowed(
        db,
        user_id=user_id,
        backup_checksum=backup_checksum,
        import_mode=import_mode,
    )


def assert_backup_import_allowed(
    db: Session,
    *,
    user_id: int,
    backup_checksum: str,
    import_mode: str,
) -> None:
    """قبل از ایجاد کسب‌وکار جدید: همان فایل نباید قبلاً import شده باشد."""
    from adapters.db.models.business_backup_import_log import BusinessBackupImportLog

    if import_mode not in ("new_business", "legacy_api"):
        return
    existing = (
        db.query(BusinessBackupImportLog)
        .filter(
            BusinessBackupImportLog.user_id == int(user_id),
            BusinessBackupImportLog.backup_checksum == backup_checksum,
            BusinessBackupImportLog.import_mode == import_mode,
        )
        .first()
    )
    if existing:
        from app.core.responses import ApiError

        raise ApiError(
            "BACKUP_ALREADY_IMPORTED",
            "این فایل پشتیبان قبلاً برای ایجاد کسب‌وکار جدید استفاده شده است.",
            http_status=409,
            details={"previous_target_business_id": existing.target_business_id},
        )


def register_backup_import(
    db: Session,
    *,
    user_id: int,
    backup_checksum: str,
    import_mode: str,
    source_business_id: Optional[int],
    target_business_id: int,
) -> None:
    """ثبت موفقیت‌آمیز ایمپورت new_business (با گارد IntegrityError)."""
    from adapters.db.models.business_backup_import_log import BusinessBackupImportLog

    if import_mode not in ("new_business", "legacy_api"):
        return
    try:
        db.add(
            BusinessBackupImportLog(
                user_id=int(user_id),
                backup_checksum=backup_checksum,
                import_mode=import_mode,
                source_business_id=source_business_id,
                target_business_id=int(target_business_id),
            )
        )
        db.flush()
    except IntegrityError:
        db.rollback()
        from app.core.responses import ApiError

        raise ApiError(
            "BACKUP_ALREADY_IMPORTED",
            "این فایل پشتیبان قبلاً برای ایجاد کسب‌وکار جدید استفاده شده است.",
            http_status=409,
        )


def purge_excluded_financial_data(db: Session, business_id: int) -> None:
    """حذف داده‌های مالی/اعتباری tenant (ایمن‌سازی پس از restore یا بکاپ قدیمی)."""
    bid = int(business_id)
    for table in sorted(BACKUP_EXCLUDED_TABLES):
        try:
            db.execute(
                text(f'DELETE FROM "{table}" WHERE business_id = :bid'),
                {"bid": bid},
            )
        except Exception as e:
            logger.warning("purge excluded table %s for business %s: %s", table, bid, e)
    db.flush()


def reset_wallet_balances(db: Session, business_id: int) -> None:
    """حساب کیف‌پول با موجودی صفر (ایجاد در صورت نبود)."""
    from app.services.wallet_service import _ensure_wallet_account

    account = _ensure_wallet_account(db, int(business_id))
    account.available_balance = Decimal("0")
    account.pending_balance = Decimal("0")
    account.status = "active"
    db.flush()


def finalize_financial_state_after_restore(db: Session, business_id: int) -> None:
    """پس از هر restore/import: پاک‌سازی entitlementها + کیف‌پول صفر."""
    purge_excluded_financial_data(db, business_id)
    reset_wallet_balances(db, business_id)
