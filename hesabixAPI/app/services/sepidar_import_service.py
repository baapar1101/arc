from __future__ import annotations

import hashlib
import asyncio
import json
import logging
from contextlib import contextmanager
from datetime import date, datetime, time, timedelta
from decimal import Decimal
from typing import Any
from uuid import UUID

from sqlalchemy import or_, text
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from adapters.db.models.sepidar_live_import import SepidarImportRow, SepidarImportRun, SepidarImportSetting
from app.services.encryption_service import EncryptionService

logger = logging.getLogger(__name__)


class SyncAlreadyRunning(ValueError):
    pass


def plugin_active(db: Session, business_id: int) -> bool:
    from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin
    now = datetime.utcnow()
    return db.query(BusinessPlugin.id).join(MarketplacePlugin).filter(
        BusinessPlugin.business_id == business_id, BusinessPlugin.status == "active",
        BusinessPlugin.starts_at <= now,
        or_(BusinessPlugin.ends_at.is_(None), BusinessPlugin.ends_at >= now),
        MarketplacePlugin.code == "sepidar_live_import", MarketplacePlugin.is_active.is_(True),
    ).first() is not None


def error_message(exc: Exception) -> str:
    # SQLAlchemy exceptions can contain imported row payloads and connection details.
    # Persist only a safe category, never SQL parameters or provider credentials.
    if isinstance(exc, SyncAlreadyRunning):
        return "یک همگام‌سازی برای این کسب‌وکار در حال اجراست."
    if "18456" in str(exc):
        return "ورود به SQL Server رد شد (18456). نام کاربری، رمز و دسترسی دیتابیس را بررسی کنید."
    return f"همگام‌سازی یا اتصال ناموفق بود ({type(exc).__name__}). تنظیمات اتصال و دسترسی خواندن را بررسی کنید."


@contextmanager
def _sync_lock(db: Session, business_id: int):
    # A dedicated physical connection keeps the session lock across batch commits.
    with db.get_bind().connect().execution_options(isolation_level="AUTOCOMMIT") as connection:
        params = {"namespace": 5457232, "business_id": business_id}
        acquired = connection.execute(text("SELECT pg_try_advisory_lock(:namespace, :business_id)"), params).scalar()
        if not acquired:
            raise SyncAlreadyRunning()
        try:
            yield
        finally:
            try:
                connection.execute(text("SELECT pg_advisory_unlock(:namespace, :business_id)"), params)
            except Exception:
                connection.invalidate()


def _json_value(value: Any) -> Any:
    if isinstance(value, (datetime, date, time)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return str(value)
    if isinstance(value, (bytes, bytearray, memoryview)):
        return bytes(value).hex()
    if isinstance(value, UUID):
        return str(value)
    return value


def public_setting(row: SepidarImportSetting | None) -> dict[str, Any]:
    if not row:
        return {"configured": False, "enabled": False, "port": 1433, "sync_interval_minutes": 15, "batch_size": 500}
    return {
        "configured": True, "host": row.host, "port": row.port, "database_name": row.database_name,
        "username": row.username, "password_configured": bool(row.password_encrypted), "enabled": row.enabled,
        "sync_interval_minutes": row.sync_interval_minutes, "batch_size": row.batch_size,
        "included_schemas": row.included_schemas or [], "included_tables": row.included_tables or [],
        "last_started_at": row.last_started_at.isoformat() if row.last_started_at else None,
        "last_success_at": row.last_success_at.isoformat() if row.last_success_at else None, "last_error": row.last_error,
    }


def save_setting(db: Session, business_id: int, payload: dict[str, Any]) -> SepidarImportSetting:
    row = db.query(SepidarImportSetting).filter_by(business_id=business_id).first()
    if not row:
        row = SepidarImportSetting(business_id=business_id, host="", database_name="", username="", password_encrypted="")
        db.add(row)
    for key in ("host", "database_name", "username"):
        if key in payload:
            setattr(row, key, str(payload[key]).strip())
    row.port = max(1, min(65535, int(payload.get("port", row.port or 1433))))
    row.enabled = bool(payload.get("enabled", row.enabled))
    row.sync_interval_minutes = max(1, min(1440, int(payload.get("sync_interval_minutes", row.sync_interval_minutes or 15))))
    row.batch_size = max(50, min(5000, int(payload.get("batch_size", row.batch_size or 500))))
    if "included_schemas" in payload:
        row.included_schemas = [str(v) for v in payload["included_schemas"] if str(v).strip()]
    if "included_tables" in payload:
        row.included_tables = [str(v) for v in payload["included_tables"] if str(v).strip()]
    if payload.get("password"):
        row.password_encrypted = EncryptionService().encrypt(str(payload["password"]))
    if not all((row.host, row.database_name, row.username, row.password_encrypted)):
        raise ValueError("اطلاعات اتصال سپیدار کامل نیست.")
    db.commit(); db.refresh(row)
    return row


def _connect(row: SepidarImportSetting):
    import pymssql
    return pymssql.connect(server=row.host, port=row.port, user=row.username,
                           password=EncryptionService().decrypt(row.password_encrypted),
                           database=row.database_name, login_timeout=10, timeout=30, as_dict=True)


def discover(row: SepidarImportSetting) -> list[dict[str, Any]]:
    with _connect(row) as conn:
        cur = conn.cursor(as_dict=True)
        cur.execute("""
            SELECT t.TABLE_SCHEMA AS schema_name, t.TABLE_NAME AS table_name,
                   COALESCE(SUM(p.rows), 0) AS row_count
            FROM INFORMATION_SCHEMA.TABLES t
            LEFT JOIN sys.tables st ON st.name=t.TABLE_NAME AND SCHEMA_NAME(st.schema_id)=t.TABLE_SCHEMA
            LEFT JOIN sys.partitions p ON p.object_id=st.object_id AND p.index_id IN (0,1)
            WHERE t.TABLE_TYPE='BASE TABLE'
            GROUP BY t.TABLE_SCHEMA,t.TABLE_NAME ORDER BY t.TABLE_SCHEMA,t.TABLE_NAME
        """)
        return [{"schema": r["schema_name"], "table": r["table_name"], "rows": int(r["row_count"] or 0)} for r in cur.fetchall()]


def test_connection(row: SepidarImportSetting) -> dict[str, Any]:
    tables = discover(row)
    return {"ok": True, "tables": len(tables), "estimated_rows": sum(t["rows"] for t in tables), "sample": tables[:20]}


def _primary_keys(cur, schema: str, table: str) -> list[str]:
    cur.execute("""
      SELECT k.COLUMN_NAME FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS c
      JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE k ON c.CONSTRAINT_NAME=k.CONSTRAINT_NAME AND c.TABLE_SCHEMA=k.TABLE_SCHEMA
      WHERE c.CONSTRAINT_TYPE='PRIMARY KEY' AND c.TABLE_SCHEMA=%s AND c.TABLE_NAME=%s ORDER BY k.ORDINAL_POSITION
    """, (schema, table))
    return [r["COLUMN_NAME"] for r in cur.fetchall()]


def run_sync(db: Session, business_id: int, *, scheduled: bool = False) -> dict[str, Any]:
    with _sync_lock(db, business_id):
        # Another worker may have finished while this worker was waiting for a connection.
        db.expire_all()
        return _run_sync(db, business_id, scheduled=scheduled)


def _run_sync(db: Session, business_id: int, *, scheduled: bool = False) -> dict[str, Any]:
    setting = db.query(SepidarImportSetting).filter_by(business_id=business_id).first()
    if not setting:
        raise ValueError("تنظیمات سپیدار ثبت نشده است.")
    if scheduled:
        if not setting.enabled or not plugin_active(db, business_id):
            return {"status": "skipped"}
        if setting.last_started_at and setting.last_started_at + timedelta(minutes=setting.sync_interval_minutes) > datetime.utcnow():
            return {"status": "skipped"}
    run = SepidarImportRun(business_id=business_id, status="running")
    db.add(run); setting.last_started_at = datetime.utcnow(); setting.last_error = None; db.commit(); db.refresh(run)
    try:
        catalog = discover(setting)
        schema_filter = set(setting.included_schemas or [])
        table_filter = set(setting.included_tables or [])
        selected = [t for t in catalog if (not schema_filter or t["schema"] in schema_filter)
                    and (not table_filter or f'{t["schema"]}.{t["table"]}' in table_filter)]
        run.tables_total = len(selected); db.commit()
        now = datetime.utcnow()
        with _connect(setting) as conn:
            cur = conn.cursor(as_dict=True)
            for item in selected:
                schema, table = item["schema"], item["table"]
                keys = _primary_keys(cur, schema, table)
                cur.execute(f"SELECT * FROM [{schema.replace(']', ']]')}].[{table.replace(']', ']]')}]")
                occurrences: dict[str, int] = {}
                while True:
                    rows = cur.fetchmany(setting.batch_size)
                    if not rows: break
                    values = []
                    for raw in rows:
                        payload = {str(k): _json_value(v) for k, v in raw.items()}
                        canonical = json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
                        content_hash = hashlib.sha256(canonical.encode()).hexdigest()
                        if keys:
                            key_json = json.dumps([payload.get(k) for k in keys], ensure_ascii=False, default=str)
                            source_key = "pk:" + hashlib.sha256(key_json.encode()).hexdigest()
                        else:
                            # No reliable identity exists without a primary key. Preserve identical
                            # duplicates while remaining independent of SQL Server's row order.
                            occurrences[content_hash] = occurrences.get(content_hash, 0) + 1
                            source_key = f"{content_hash}:{occurrences[content_hash]}"
                        values.append({"business_id": business_id, "source_schema": schema, "source_table": table,
                                       "source_key": source_key, "payload": payload,
                                       "content_hash": content_hash,
                                       "first_seen_at": now, "last_seen_at": now})
                    stmt = insert(SepidarImportRow).values(values)
                    stmt = stmt.on_conflict_do_update(
                        constraint="uq_sepidar_import_row_source",
                        set_={"payload": stmt.excluded.payload, "content_hash": stmt.excluded.content_hash, "last_seen_at": now},
                        where=SepidarImportRow.content_hash != stmt.excluded.content_hash)
                    result = db.execute(stmt); db.commit()
                    run.rows_seen += len(values); run.rows_changed += max(0, result.rowcount or 0); db.commit()
                run.tables_completed += 1; db.commit()
        run.status = "success"; run.finished_at = datetime.utcnow(); setting.last_success_at = run.finished_at; setting.last_error = None; db.commit()
        return {"run_id": run.id, "status": run.status, "tables": run.tables_completed, "rows_seen": run.rows_seen, "rows_changed": run.rows_changed}
    except Exception as exc:
        db.rollback(); run = db.get(SepidarImportRun, run.id); setting = db.get(SepidarImportSetting, setting.id)
        message = error_message(exc); run.status = "failed"; run.error = message; run.finished_at = datetime.utcnow(); setting.last_error = message; db.commit()
        raise


def recent_runs(db: Session, business_id: int) -> list[dict[str, Any]]:
    rows = db.query(SepidarImportRun).filter_by(business_id=business_id).order_by(SepidarImportRun.id.desc()).limit(20).all()
    return [{"id": r.id, "status": r.status, "tables_total": r.tables_total, "tables_completed": r.tables_completed,
             "rows_seen": r.rows_seen, "rows_changed": r.rows_changed, "error": r.error,
             "started_at": r.started_at.isoformat(), "finished_at": r.finished_at.isoformat() if r.finished_at else None} for r in rows]


def _run_due_settings() -> None:
    from adapters.db.session import SessionLocal
    db = SessionLocal()
    try:
        now = datetime.utcnow()
        settings = db.query(SepidarImportSetting).filter(SepidarImportSetting.enabled == True).all()  # noqa: E712
        for row in settings:
            due = not row.last_started_at or row.last_started_at + timedelta(minutes=row.sync_interval_minutes) <= now
            if due:
                try:
                    run_sync(db, int(row.business_id), scheduled=True)
                except Exception:
                    db.rollback()
    finally:
        db.close()


async def sepidar_import_background_loop() -> None:
    while True:
        try:
            await asyncio.to_thread(_run_due_settings)
        except Exception as exc:
            logger.warning("Sepidar scheduler failed (%s); retrying in 60 seconds", type(exc).__name__)
        await asyncio.sleep(60)
