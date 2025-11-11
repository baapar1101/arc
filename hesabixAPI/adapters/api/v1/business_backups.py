from __future__ import annotations

import io
import json
import zipfile
from datetime import datetime, date
from decimal import Decimal
from typing import Any, Dict, List

from fastapi import APIRouter, Depends, Request, UploadFile, File, Body, BackgroundTasks
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from sqlalchemy import inspect, text

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access_dep
from app.core.responses import success_response, ApiError
from app.services.file_storage_service import FileStorageService
import logging
from app.services.job_manager import JobManager


router = APIRouter(prefix="/businesses/{business_id}/backups", tags=["business_backups"])

def _json_default(o: Any):
    if isinstance(o, (datetime, date)):
        return o.isoformat()
    if isinstance(o, Decimal):
        return str(o)
    return str(o)


def _discover_scoped_tables(db: Session) -> Dict[str, Dict[str, Any]]:
    """
    جداول مرتبط با دامنه کسب‌وکار را به‌صورت پویا کشف می‌کند.
    راهکار پایه: هر جدول دارای ستون business_id + خود جدول businesses.
    این پیاده‌سازی قابل توسعه است تا مسیرهای غیرمستقیم FK را نیز پوشش دهد.
    """
    engine = db.get_bind()
    inspector = inspect(engine)
    tables_info: Dict[str, Dict[str, Any]] = {}
    for table_name in inspector.get_table_names():
        try:
            cols = inspector.get_columns(table_name)
        except Exception:
            continue
        col_names = {c["name"] for c in cols}
        if "business_id" in col_names or table_name == "businesses":
            pk_cols = inspector.get_pk_constraint(table_name).get("constrained_columns") or []
            tables_info[table_name] = {
                "columns": [c["name"] for c in cols],
                "pk": pk_cols,
            }
    return tables_info


def _dump_business_data(db: Session, business_id: int) -> Dict[str, Any]:
    """
    داده‌های tenant-scoped را به‌صورت پویا با شرط business_id استخراج می‌کند.
    خروجی: { metadata, tables: {table: [rows...] } }
    """
    tables = _discover_scoped_tables(db)
    engine = db.get_bind()
    data_out: Dict[str, List[Dict[str, Any]]] = {}

    for table_name, meta in tables.items():
        if table_name == "businesses":
            stmt = text(f"SELECT * FROM {table_name} WHERE id = :bid")
            rows = [dict(r._mapping) for r in db.execute(stmt, {"bid": business_id}).all()]
        else:
            # جداولی که ستون business_id دارند
            stmt = text(f"SELECT * FROM {table_name} WHERE business_id = :bid")
            try:
                rows = [dict(r._mapping) for r in db.execute(stmt, {"bid": business_id}).all()]
            except Exception:
                rows = []
        data_out[table_name] = rows

    metadata = {
        "schema_version": "v1",
        "created_at": datetime.utcnow().isoformat(),
        "business_id": business_id,
        "tables": list(data_out.keys()),
    }
    return {"metadata": metadata, "tables": data_out}


@router.get("", dependencies=[Depends(require_business_access_dep)])
async def list_backups(
    request: Request,
    business_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """
    فهرست بکاپ‌های ثبت‌شده برای این کسب‌وکار.
    توجه: از developer_data برای فیلتر بر اساس business_id استفاده می‌کنیم.
    """
    from adapters.db.models.file_storage import FileStorage
    q = (
        db.query(FileStorage)
        .filter(
            FileStorage.module_context == "business_backup",
            FileStorage.deleted_at.is_(None),
        )
        .order_by(FileStorage.created_at.desc())
    )
    items = []
    # فیلتر JSON (سازگار با MySQL JSON)
    for f in q.all():
        dev = f.developer_data or {}
        bid_val = dev.get("business_id")
        same_business = False
        if isinstance(bid_val, int):
            same_business = (bid_val == business_id)
        else:
            try:
                same_business = (int(str(bid_val)) == int(business_id))
            except Exception:
                same_business = False
        if same_business:
            items.append(
                {
                    "id": str(f.id),
                    "filename": f.original_name,
                    "size": f.file_size,
                    "created_at": f.created_at.isoformat() if f.created_at else None,
                    "checksum": f.checksum,
                    "mime_type": f.mime_type,
                }
            )
    return success_response({"items": items}, request=request)


def _perform_backup(db: Session, ctx: AuthContext, business_id: int, job_id: str | None = None) -> Dict[str, Any]:
    """اجرای هم‌زمان بکاپ (برای استفاده در background task نیز)"""
    jm = JobManager.instance()
    try:
        if job_id:
            jm.start(job_id, "Starting backup")
            jm.update(job_id, 10, "Collecting data")
        snapshot = _dump_business_data(db, business_id)
        if job_id:
            jm.update(job_id, 50, "Packaging archive")

        buf = io.BytesIO()
        with zipfile.ZipFile(buf, mode="w", compression=zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("metadata.json", json.dumps(snapshot["metadata"], ensure_ascii=False, indent=2, default=_json_default))
            for table_name, rows in snapshot["tables"].items():
                out = io.StringIO()
                for row in rows:
                    out.write(json.dumps(row, ensure_ascii=False, default=_json_default))
                    out.write("\n")
                zf.writestr(f"tables/{table_name}.jsonl", out.getvalue().encode("utf-8"))

        if job_id:
            jm.update(job_id, 70, "Saving file")
        buf.seek(0)
        filename = f"business_{business_id}_backup_{datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')}.hbx"
        # اینجا فقط خروجی ساخت ZIP را برمی‌گردانیم.
        result = {
            "zip_bytes": buf.getvalue(),
            "metadata": snapshot["metadata"],
            "filename": filename,
        }
        if job_id:
            jm.update(job_id, 90, "Finalizing")
        return result
    except Exception as e:
        if job_id:
            jm.fail(job_id, str(e), "Backup failed")
        raise


@router.post("", dependencies=[Depends(require_business_access_dep)])
async def create_backup(
    request: Request,
    business_id: int,
    async_mode: bool = True,
    background: BackgroundTasks = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """
    ایجاد بکاپ پویا. به‌صورت پیش‌فرض غیرهمزمان اجرا می‌شود و job_id برمی‌گرداند.
    """
    if async_mode:
        jm = JobManager.instance()
        job_id = jm.create("Backup queued")

        def task():
            # اجرای بکاپ و ذخیره فایل
            try:
                data = _perform_backup(db, ctx, business_id, job_id=job_id)
                jm.update(job_id, 92, "Uploading file")
                faux_upload = UploadFile(filename=data["filename"], file=io.BytesIO(data["zip_bytes"]))
                storage = FileStorageService(db)
                import anyio
                async def _upload():
                    saved = await storage.upload_file(
                        faux_upload,
                        user_id=ctx.get_user_id(),
                        module_context="business_backup",
                        developer_data={
                            "business_id": business_id,
                            "schema_version": data["metadata"]["schema_version"],
                        },
                        is_temporary=False,
                        expires_in_days=3650,
                    )
                    return saved
                saved = anyio.run(_upload)
                jm.succeed(job_id, {"file": saved, "metadata": data["metadata"]}, "Backup completed")
            except Exception as e:
                jm.fail(job_id, str(e), "Backup failed")

        background.add_task(task)
        return success_response({"job_id": job_id}, request=request, message="Backup started")
    else:
        # مسیر هم‌زمان قدیمی
        data = _perform_backup(db, ctx, business_id)
        faux_upload = UploadFile(filename=data["filename"], file=io.BytesIO(data["zip_bytes"]))
        storage = FileStorageService(db)
        saved = await storage.upload_file(
            faux_upload,
            user_id=ctx.get_user_id(),
            module_context="business_backup",
            developer_data={
                "business_id": business_id,
                "schema_version": data["metadata"]["schema_version"],
            },
            is_temporary=False,
            expires_in_days=3650,
        )
        return success_response({"file": saved, "metadata": data["metadata"]}, request=request, message="Backup created")


@router.get("/{backup_id}/download", dependencies=[Depends(require_business_access_dep)])
async def download_backup(
    request: Request,
    business_id: int,
    backup_id: str,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """
    دانلود فایل بکاپ.
    """
    from uuid import UUID
    storage = FileStorageService(db)
    try:
        file_data = await storage.download_file(UUID(backup_id))
    except Exception as e:
        raise ApiError("FILE_NOT_FOUND", f"Backup not found: {e}", http_status=404)

    return StreamingResponse(
        io.BytesIO(file_data["content"]),
        media_type=file_data["mime_type"] or "application/zip",
        headers={"Content-Disposition": f'attachment; filename="{file_data["filename"]}"'},
    )


@router.delete("/{backup_id}", dependencies=[Depends(require_business_access_dep)])
async def delete_backup(
    request: Request,
    business_id: int,
    backup_id: str,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """
    حذف نرم فایل بکاپ.
    """
    from uuid import UUID
    import os
    from adapters.db.models.file_storage import FileStorage
    # ابتدا فایل را بدون فیلتر deleted پیدا می‌کنیم تا ایدمپوتنت باشد
    file = db.query(FileStorage).filter(FileStorage.id == str(UUID(backup_id))).first()
    if not file:
        raise ApiError("FILE_NOT_FOUND", "Backup not found", http_status=404)
    # اعتبارسنجی اینکه این فایل بکاپ همین کسب‌وکار است
    dev = file.developer_data or {}
    bid_val = dev.get("business_id")
    same_business = False
    if isinstance(bid_val, int):
        same_business = (bid_val == business_id)
    else:
        try:
            same_business = (int(str(bid_val)) == int(business_id))
        except Exception:
            same_business = False
    if file.module_context != "business_backup" or not same_business:
        # برای جلوگیری از حذف فایل‌های سایر کسب‌وکارها
        raise ApiError("FILE_NOT_FOUND", "Backup not found", http_status=404)
    # لاگ برای بررسی وضعیت فایل روی دیسک قبل از حذف
    try:
        logger = logging.getLogger(__name__)
        logger.info(
            "backup_delete_request",
            extra={
                "backup_id": backup_id,
                "business_id": business_id,
                "path": file.file_path,
                "storage_type": file.storage_type,
                "exists_before": os.path.exists(file.file_path),
                "deleted_at": str(file.deleted_at) if file.deleted_at else None,
            },
        )
    except Exception:
        pass
    # تلاش برای حذف فیزیکی حتی اگر قبلاً soft-delete شده باشد
    storage = FileStorageService(db)
    try:
        await storage._delete_file_from_storage(file.file_path, file.storage_type)  # type: ignore[attr-defined]
    except Exception:
        pass
    # اگر قبلاً soft-delete نشده، انجام ده؛ در غیر این صورت نتیجه موفق ایدمپوتنت برگردان
    if file.deleted_at is None:
        ok = await storage.delete_file(UUID(backup_id))
        if not ok:
            return success_response({"deleted": True}, request=request)
    return success_response({"deleted": True}, request=request)


@router.post("/restore")
async def restore_backup(
    request: Request,
    business_id: int,
    backup_id: str | None = Body(default=None),
    file: UploadFile | None = File(default=None),
    mode: str = Body(default="new_business", embed=True),
    async_mode: bool = True,
    background: BackgroundTasks = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """
    بازیابی داده‌ها از بکاپ.
    - پشتیبانی شده: mode == "replace" → جایگزینی کامل داده‌های مرتبط با business_id جاری
    - پشتیبانی نشده فعلاً: mode == "new_business"
    """
    logger = logging.getLogger(__name__)
    if not (backup_id or file):
        raise ApiError("INVALID_INPUT", "backup_id or file is required")
    if mode not in ("replace", "new_business"):
        raise ApiError("INVALID_INPUT", "mode must be one of: replace, new_business")

    # محدودسازی نرخ ساده (هر کاربر هر 60 ثانیه یکبار)
    try:
        _rate_limiter_key = ("restore", ctx.get_user_id())
        if not hasattr(restore_backup, "_last_calls"):
            restore_backup._last_calls = {}  # type: ignore[attr-defined]
        last_calls = restore_backup._last_calls  # type: ignore[attr-defined]
        from time import time
        now = time()
        if _rate_limiter_key in last_calls and (now - last_calls[_rate_limiter_key]) < 60:
            raise ApiError("RATE_LIMIT", "Too many restore attempts. Please wait.", http_status=429)
        last_calls[_rate_limiter_key] = now
    except Exception:
        # در صورت خطا در limiter، ادامه می‌دهیم ولی لاگ می‌کنیم
        logger.warning("Restore rate limiter failure; continuing")

    if async_mode:
        jm = JobManager.instance()
        job_id = jm.create("Restore queued")

        async def _load_zip() -> bytes:
            if backup_id:
                from uuid import UUID
                storage = FileStorageService(db)
                file_data = await storage.download_file(UUID(backup_id))
                return file_data["content"]
            else:
                return await file.read()  # type: ignore[union-attr]

        def task():
            try:
                jm.start(job_id, "Starting restore")
                jm.update(job_id, 10, "Loading backup")
                import anyio
                zip_bytes = anyio.run(_load_zip)
                buf = io.BytesIO(zip_bytes)
                with zipfile.ZipFile(buf, mode="r") as zf:
                    try:
                        metadata = json.loads(zf.read("metadata.json").decode("utf-8"))
                    except KeyError:
                        raise ApiError("INVALID_BACKUP", "metadata.json not found in backup")

                    snapshot_business_id = metadata.get("business_id")
                    if mode == "replace" and int(business_id) != int(snapshot_business_id):
                        raise ApiError("BUSINESS_MISMATCH", "Backup belongs to a different business")
                    if mode == "new_business":
                        raise ApiError("NOT_SUPPORTED", "new_business mode is not implemented yet")

                    tables_info = _discover_scoped_tables(db)
                    target_tables = [t for t in tables_info.keys() if t != "businesses"]

                    conn = db.connection()
                    try:
                        conn.execute(text("SET FOREIGN_KEY_CHECKS=0"))
                    except Exception:
                        pass

                    try:
                        jm.update(job_id, 40, "Cleaning current data")
                        for table in target_tables:
                            cols = tables_info[table]["columns"]
                            if "business_id" in cols:
                                conn.execute(text(f"DELETE FROM {table} WHERE business_id = :bid"), {"bid": business_id})

                        # Update business row if present
                        jm.update(job_id, 55, "Updating business info")
                        if "businesses" in tables_info:
                            try:
                                rows = []
                                with zf.open("tables/businesses.jsonl", "r") as f:
                                    for raw in f:
                                        if not raw:
                                            continue
                                        rows.append(json.loads(raw.decode("utf-8")))
                                row = next((r for r in rows if int(r.get("id")) == int(business_id)), None)
                                if row:
                                    cols = [c for c in tables_info["businesses"]["columns"] if c not in ("id", "created_at", "updated_at")]
                                    assignments = ", ".join([f"{c} = :{c}" for c in cols])
                                    params = {c: row.get(c) for c in cols}
                                    params["id"] = business_id
                                    conn.execute(text(f"UPDATE businesses SET {assignments} WHERE id = :id"), params)
                            except KeyError:
                                pass

                        # Insert data for other tables
                        jm.update(job_id, 70, "Restoring data")
                        for table in target_tables:
                            try:
                                zinfo = zf.getinfo(f"tables/{table}.jsonl")
                            except KeyError:
                                continue
                            col_list = tables_info[table]["columns"]
                            placeholders = ", ".join([f":{c}" for c in col_list])
                            columns_sql = ", ".join([f"`{c}`" for c in col_list])
                            insert_sql = text(f"INSERT INTO {table} ({columns_sql}) VALUES ({placeholders})")
                            batch: List[Dict[str, Any]] = []
                            with zf.open(f"tables/{table}.jsonl", "r") as f:
                                for raw in f:
                                    if not raw:
                                        continue
                                    rec = json.loads(raw.decode("utf-8"))
                                    if "business_id" in rec:
                                        rec["business_id"] = business_id
                                    params = {c: rec.get(c) for c in col_list}
                                    batch.append(params)
                                    if len(batch) >= 500:
                                        conn.execute(insert_sql, batch)
                                        batch.clear()
                            if batch:
                                conn.execute(insert_sql, batch)

                        try:
                            conn.execute(text("SET FOREIGN_KEY_CHECKS=1"))
                        except Exception:
                            pass
                        db.commit()
                    except Exception as e:
                        db.rollback()
                        try:
                            conn.execute(text("SET FOREIGN_KEY_CHECKS=1"))
                        except Exception:
                            pass
                        raise

                jm.succeed(job_id, {"restored": True, "mode": mode, "business_id": business_id}, "Restore completed")
            except Exception as e:
                jm.fail(job_id, str(e), "Restore failed")

        background.add_task(task)
        return success_response({"job_id": job_id}, request=request, message="Restore started")
    else:
        # مسیر هم‌زمان قبلی (همان منطق، بدون job)
        # برای اختصار، از مسیر async استفاده کنید؛ این شاخه برای سازگاری باقی می‌ماند
        raise ApiError("SYNC_DISABLED", "Use async_mode=true for restore")


