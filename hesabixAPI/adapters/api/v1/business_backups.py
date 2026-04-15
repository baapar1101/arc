from __future__ import annotations

import io
import json
import os
import tempfile
import zipfile
from datetime import datetime, date
from decimal import Decimal
from typing import Any, Dict, List

from fastapi import APIRouter, Depends, Request, UploadFile, File, Body, BackgroundTasks
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from sqlalchemy import inspect, text
from pydantic import BaseModel, Field

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access_dep
from app.core.responses import success_response, ApiError
from app.services.file_storage_service import FileStorageService
from app.services.business_service import create_business
from adapters.api.v1.schemas import BusinessCreateRequest, BusinessType, BusinessField
import logging
from app.services.job_manager import JobManager
from adapters.api.v1.business_ftp_backup import assert_can_use_ftp_on_backup, upload_saved_backup_to_ftp
from app.services.business_ftp_service import load_decrypted_params

logger = logging.getLogger(__name__)


def _merge_backup_ftp_metadata(db: Session, file_id: str, ftp_info: dict[str, Any]) -> None:
	from adapters.db.models.file_storage import FileStorage
	from sqlalchemy.orm.attributes import flag_modified

	fs = db.query(FileStorage).filter(FileStorage.id == file_id).first()
	if not fs:
		return
	dev = dict(fs.developer_data or {})
	dev["ftp_uploaded"] = True
	dev["ftp_remote_path"] = ftp_info.get("remote_path")
	dev["ftp_remote_filename"] = ftp_info.get("remote_filename")
	dev["ftp_transport"] = ftp_info.get("transport")
	fs.developer_data = dev
	flag_modified(fs, "developer_data")
	db.add(fs)
	db.commit()

router = APIRouter(prefix="/businesses/{business_id}/backups", tags=["پشتیبان‌گیری"])


class RestoreBackupRequest(BaseModel):
    backup_id: str | None = Field(default=None, description="شناسه بکاپ برای بازیابی")
    mode: str = Field(default="new_business", description="حالت بازیابی: replace یا new_business")


class CreateBackupBody(BaseModel):
    upload_to_ftp: bool = Field(default=False, description="پس از ذخیره داخلی، ارسال کپی به سرور FTP")


def _normalize_business_type(value: Any) -> BusinessType:
    """
    تبدیل business_type از بکاپ به BusinessType enum.
    پشتیبانی از enum name (مثل 'SHOP') و مقدار فارسی (مثل 'مغازه').
    """
    if value is None:
        return BusinessType.COMPANY
    
    value_str = str(value).strip()
    
    # اگر مقدار فارسی است، مستقیماً استفاده می‌کنیم
    persian_values = {
        "شرکت": BusinessType.COMPANY,
        "مغازه": BusinessType.SHOP,
        "فروشگاه": BusinessType.STORE,
        "اتحادیه": BusinessType.UNION,
        "باشگاه": BusinessType.CLUB,
        "موسسه": BusinessType.INSTITUTE,
        "شخصی": BusinessType.INDIVIDUAL,
    }
    if value_str in persian_values:
        return persian_values[value_str]
    
    # اگر enum name است (مثل 'SHOP', 'COMPANY')
    enum_name_to_type = {
        "COMPANY": BusinessType.COMPANY,
        "SHOP": BusinessType.SHOP,
        "STORE": BusinessType.STORE,
        "UNION": BusinessType.UNION,
        "CLUB": BusinessType.CLUB,
        "INSTITUTE": BusinessType.INSTITUTE,
        "INDIVIDUAL": BusinessType.INDIVIDUAL,
    }
    if value_str.upper() in enum_name_to_type:
        return enum_name_to_type[value_str.upper()]
    
    # تلاش برای پیدا کردن در enum
    try:
        return BusinessType(value_str)
    except ValueError:
        # اگر پیدا نشد، پیش‌فرض شرکت
        return BusinessType.COMPANY


def _normalize_business_field(value: Any) -> BusinessField:
    """
    تبدیل business_field از بکاپ به BusinessField enum.
    پشتیبانی از enum name (مثل 'MANUFACTURING', 'COMMERCIAL', 'TRADING') و مقدار فارسی (مثل 'تولیدی').
    """
    if value is None:
        return BusinessField.OTHER
    
    value_str = str(value).strip()
    
    # اگر مقدار فارسی است، مستقیماً استفاده می‌کنیم
    persian_values = {
        "تولیدی": BusinessField.MANUFACTURING,
        "بازرگانی": BusinessField.COMMERCIAL,  # در schemas.py این COMMERCIAL است نه TRADING
        "خدماتی": BusinessField.SERVICE,
        "سایر": BusinessField.OTHER,
    }
    if value_str in persian_values:
        return persian_values[value_str]
    
    # اگر enum name است (مثل 'MANUFACTURING', 'COMMERCIAL', 'TRADING')
    # توجه: در schemas.py این COMMERCIAL است، اما در db/models ممکن است TRADING باشد
    enum_name_to_field = {
        "MANUFACTURING": BusinessField.MANUFACTURING,
        "COMMERCIAL": BusinessField.COMMERCIAL,  # نام صحیح در schemas.py
        "TRADING": BusinessField.COMMERCIAL,  # تبدیل TRADING به COMMERCIAL (برای سازگاری)
        "SERVICE": BusinessField.SERVICE,
        "OTHER": BusinessField.OTHER,
    }
    if value_str.upper() in enum_name_to_field:
        return enum_name_to_field[value_str.upper()]
    
    # تلاش برای پیدا کردن در enum
    try:
        return BusinessField(value_str)
    except ValueError:
        # اگر پیدا نشد، پیش‌فرض سایر
        return BusinessField.OTHER


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
                    "ftp_uploaded": bool(dev.get("ftp_uploaded")),
                    "ftp_remote_filename": dev.get("ftp_remote_filename"),
                    "ftp_transport": dev.get("ftp_transport"),
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
            # استخراج error message به صورت مناسب
            error_msg = None
            error_code = None
            error_details = None
            
            # بررسی ApiError یا HTTPException
            from fastapi import HTTPException
            if isinstance(e, (ApiError, HTTPException)):
                if hasattr(e, 'detail') and isinstance(e.detail, dict):
                    error_info = e.detail.get("error", {})
                    if isinstance(error_info, dict):
                        error_code = error_info.get("code")
                        error_msg = error_info.get("message")
                        error_details = error_info.get("details")
                elif isinstance(e.detail, str):
                    error_msg = e.detail
            
            # اگر error message پیدا نشد، از str(e) استفاده کن
            if not error_msg:
                error_msg = str(e) if e else "Unknown error"
                if not error_msg or error_msg.strip() == "":
                    error_msg = f"Backup failed: {type(e).__name__}"
            
            # ساخت error message مناسب برای frontend
            if error_code:
                final_error = f"{error_code}: {error_msg}"
                if error_details:
                    final_error += f" | Details: {error_details}"
            else:
                final_error = error_msg
            
            jm.fail(job_id, final_error, "Backup failed")
        raise


@router.post("", dependencies=[Depends(require_business_access_dep)])
async def create_backup(
    request: Request,
    business_id: int,
    async_mode: bool = True,
    background: BackgroundTasks = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    body: CreateBackupBody | None = Body(None),
):
    """
    ایجاد بکاپ پویا. به‌صورت پیش‌فرض غیرهمزمان اجرا می‌شود و job_id برمی‌گرداند.
    """
    upload_to_ftp = bool(body.upload_to_ftp) if body else False
    if upload_to_ftp:
        assert_can_use_ftp_on_backup(db, ctx, business_id)
        if not load_decrypted_params(db, business_id):
            raise ApiError("FTP_NOT_CONFIGURED", "ابتدا تنظیمات FTP را در بخش تنظیمات ذخیره کنید", http_status=400)

    if async_mode:
        jm = JobManager.instance()
        job_id = jm.create("Backup queued")
        logger.info(f"[BACKUP] Created backup job {job_id} for business_id: {business_id}")
        do_ftp = upload_to_ftp

        def task():
            # استفاده از get_db_session برای background task
            from adapters.db.session import get_db_session
            with get_db_session() as db:
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
                            business_id=business_id,
                            check_storage_limit=True,
                        )
                        return saved
                    saved = anyio.run(_upload)
                    result_payload: Dict[str, Any] = {"file": saved, "metadata": data["metadata"]}
                    if do_ftp:
                        jm.update(job_id, 94, "Uploading to FTP")
                        tmp_path: str | None = None
                        try:
                            with tempfile.NamedTemporaryFile(suffix=".hbx", delete=False) as tf:
                                tf.write(data["zip_bytes"])
                                tmp_path = tf.name
                            ftp_info = upload_saved_backup_to_ftp(
                                db, business_id, data["filename"], data=None, file_path=tmp_path
                            )
                        finally:
                            if tmp_path and os.path.isfile(tmp_path):
                                try:
                                    os.unlink(tmp_path)
                                except OSError:
                                    pass
                        if not ftp_info:
                            raise ApiError("FTP_NOT_CONFIGURED", "تنظیمات FTP در دسترس نبود", http_status=400)
                        result_payload["ftp"] = ftp_info
                        fid = (saved or {}).get("file_id")
                        if fid:
                            _merge_backup_ftp_metadata(db, str(fid), ftp_info)
                    jm.succeed(job_id, result_payload, "Backup completed")
                except Exception as e:
                    # استخراج error message به صورت مناسب
                    error_msg = None
                    error_code = None
                    error_details = None
                    
                    # بررسی ApiError یا HTTPException
                    from fastapi import HTTPException
                    if isinstance(e, (ApiError, HTTPException)):
                        if hasattr(e, 'detail') and isinstance(e.detail, dict):
                            error_info = e.detail.get("error", {})
                            if isinstance(error_info, dict):
                                error_code = error_info.get("code")
                                error_msg = error_info.get("message")
                                error_details = error_info.get("details")
                        elif isinstance(e.detail, str):
                            error_msg = e.detail
                    
                    # اگر error message پیدا نشد، از str(e) استفاده کن
                    if not error_msg:
                        error_msg = str(e) if e else "Unknown error"
                        if not error_msg or error_msg.strip() == "":
                            error_msg = f"Backup failed: {type(e).__name__}"
                    
                    # ساخت error message مناسب برای frontend
                    if error_code:
                        final_error = f"{error_code}: {error_msg}"
                        if error_details:
                            final_error += f" | Details: {error_details}"
                    else:
                        final_error = error_msg
                    
                    jm.fail(job_id, final_error, "Backup failed")

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
            business_id=business_id,
            check_storage_limit=True,
        )
        out: Dict[str, Any] = {"file": saved, "metadata": data["metadata"]}
        if upload_to_ftp:
            tmp_path: str | None = None
            try:
                with tempfile.NamedTemporaryFile(suffix=".hbx", delete=False) as tf:
                    tf.write(data["zip_bytes"])
                    tmp_path = tf.name
                ftp_info = upload_saved_backup_to_ftp(
                    db, business_id, data["filename"], data=None, file_path=tmp_path
                )
            finally:
                if tmp_path and os.path.isfile(tmp_path):
                    try:
                        os.unlink(tmp_path)
                    except OSError:
                        pass
            if not ftp_info:
                raise ApiError("FTP_NOT_CONFIGURED", "تنظیمات FTP در دسترس نبود", http_status=400)
            out["ftp"] = ftp_info
            fid = (saved or {}).get("file_id")
            if fid:
                _merge_backup_ftp_metadata(db, str(fid), ftp_info)
        return success_response(out, request=request, message="Backup created")


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
    file: UploadFile | None = File(default=None),
    async_mode: bool = True,
    background: BackgroundTasks = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """
    بازیابی داده‌ها از بکاپ.
    - پشتیبانی شده: mode == "replace" → جایگزینی کامل داده‌های مرتبط با business_id جاری
    - پشتیبانی نشده فعلاً: mode == "new_business"
    
    می‌تواند به صورت JSON (با backup_id) یا form-data (با file) فراخوانی شود.
    """
    logger = logging.getLogger(__name__)
    
    # پردازش درخواست: می‌تواند JSON یا form-data باشد
    backup_id: str | None = None
    mode: str = "new_business"
    
    # بررسی نوع محتوا
    content_type = request.headers.get("content-type", "").lower()
    
    if "application/json" in content_type:
        # درخواست JSON - پارس کردن از body
        try:
            body_data = await request.json()
            body = RestoreBackupRequest(**body_data)
            backup_id = body.backup_id
            mode = body.mode
        except Exception as e:
            raise ApiError("INVALID_INPUT", f"Invalid JSON body: {str(e)}")
    elif "multipart/form-data" in content_type:
        # درخواست form-data
        form_data = await request.form()
        backup_id_str = form_data.get("backup_id")
        if backup_id_str:
            backup_id = str(backup_id_str)
        mode_str = form_data.get("mode")
        if mode_str:
            mode = str(mode_str)
    else:
        # تلاش برای پارس کردن به عنوان JSON
        try:
            body_data = await request.json()
            body = RestoreBackupRequest(**body_data)
            backup_id = body.backup_id
            mode = body.mode
        except Exception:
            # اگر JSON نبود، از form-data استفاده می‌کنیم
            try:
                form_data = await request.form()
                backup_id_str = form_data.get("backup_id")
                if backup_id_str:
                    backup_id = str(backup_id_str)
                mode_str = form_data.get("mode")
                if mode_str:
                    mode = str(mode_str)
            except Exception:
                pass
    
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
        logger.info(f"[RESTORE] Created restore job {job_id} for business_id: {business_id}, mode: {mode}")

        # خواندن محتوای فایل قبل از شروع background task
        # تا از بسته شدن فایل جلوگیری کنیم
        file_bytes: bytes | None = None
        if file:
            try:
                file_bytes = await file.read()
            except Exception as e:
                logger.error(f"Error reading file: {e}")
                raise ApiError("FILE_READ_ERROR", f"Failed to read uploaded file: {str(e)}")

        async def _load_zip() -> bytes:
            if backup_id:
                from uuid import UUID
                storage = FileStorageService(db)
                file_data = await storage.download_file(UUID(backup_id))
                return file_data["content"]
            elif file_bytes:
                return file_bytes
            else:
                raise ApiError("NO_FILE_DATA", "No file data available")

        def task():
            # استفاده از get_db_session برای background task
            from adapters.db.session import get_db_session
            with get_db_session() as db:
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
                        
                        # برای mode new_business، باید یک کسب‌وکار جدید ایجاد کنیم
                        new_business_id = business_id
                        if mode == "new_business":
                            jm.update(job_id, 20, "Creating new business")
                            # خواندن اطلاعات کسب‌وکار از بکاپ
                            try:
                                business_rows = []
                                with zf.open("tables/businesses.jsonl", "r") as f:
                                    for raw in f:
                                        if not raw:
                                            continue
                                        business_rows.append(json.loads(raw.decode("utf-8")))
                                
                                if not business_rows:
                                    raise ApiError("INVALID_BACKUP", "No business data found in backup")
                                
                                # استفاده از اولین ردیف کسب‌وکار (معمولاً فقط یکی وجود دارد)
                                original_business = business_rows[0]
                                
                                # ایجاد کسب‌وکار جدید با اطلاعات بکاپ
                                # تبدیل به BusinessCreateRequest
                                business_create_data = BusinessCreateRequest(
                                    name=f"{original_business.get('name', 'کسب‌وکار جدید')} (بازیابی شده)",
                                    business_type=_normalize_business_type(original_business.get('business_type')),
                                    business_field=_normalize_business_field(original_business.get('business_field')),
                                    address=original_business.get('address'),
                                    phone=original_business.get('phone'),
                                    mobile=original_business.get('mobile'),
                                    national_id=original_business.get('national_id'),
                                    registration_number=original_business.get('registration_number'),
                                    economic_id=original_business.get('economic_id'),
                                    country=original_business.get('country'),
                                    province=original_business.get('province'),
                                    city=original_business.get('city'),
                                    postal_code=original_business.get('postal_code'),
                                    default_currency_id=original_business.get('default_currency_id'),
                                    default_credit_limit=float(original_business.get('default_credit_limit')) if original_business.get('default_credit_limit') else None,
                                    check_credit_enabled_by_default=bool(original_business.get('check_credit_enabled_by_default', False)),
                                )
                                
                                # ایجاد کسب‌وکار جدید
                                new_business = create_business(db, business_create_data, ctx.get_user_id())
                                new_business_id = new_business['id']
                                db.commit()
                                jm.update(job_id, 30, f"New business created (ID: {new_business_id})")
                            except KeyError:
                                raise ApiError("INVALID_BACKUP", "businesses.jsonl not found in backup")
                            except Exception as e:
                                raise ApiError("BUSINESS_CREATION_FAILED", f"Failed to create new business: {str(e)}")

                        tables_info = _discover_scoped_tables(db)
                        target_tables = [t for t in tables_info.keys() if t != "businesses"]

                        conn = db.connection()
                        # PostgreSQL: غیرفعال کردن foreign key checks (موقت)
                        try:
                            conn.execute(text("SET session_replication_role = 'replica'"))  # PostgreSQL equivalent
                        except Exception:
                            pass

                        try:
                            # فقط برای mode replace باید داده‌های قبلی را پاک کنیم
                            if mode == "replace":
                                jm.update(job_id, 40, "Cleaning current data")
                                for table in target_tables:
                                    cols = tables_info[table]["columns"]
                                    if "business_id" in cols:
                                        conn.execute(text(f"DELETE FROM {table} WHERE business_id = :bid"), {"bid": new_business_id})
                            else:
                                jm.update(job_id, 40, "Preparing to restore data")

                            # Update business row if present (فقط برای mode replace)
                            if mode == "replace":
                                jm.update(job_id, 55, "Updating business info")
                                if "businesses" in tables_info:
                                    try:
                                        rows = []
                                        with zf.open("tables/businesses.jsonl", "r") as f:
                                            for raw in f:
                                                if not raw:
                                                    continue
                                                rows.append(json.loads(raw.decode("utf-8")))
                                        row = next((r for r in rows if int(r.get("id")) == int(snapshot_business_id)), None)
                                        if row:
                                            cols = [c for c in tables_info["businesses"]["columns"] if c not in ("id", "created_at", "updated_at", "owner_id")]
                                            assignments = ", ".join([f"{c} = :{c}" for c in cols])
                                            params = {c: row.get(c) for c in cols}
                                            params["id"] = new_business_id
                                            conn.execute(text(f"UPDATE businesses SET {assignments} WHERE id = :id"), params)
                                    except KeyError:
                                        pass
                            else:
                                jm.update(job_id, 55, "Preparing business data")

                            # Insert data for other tables
                            jm.update(job_id, 70, "Restoring data")
                            
                            for table in target_tables:
                                try:
                                    zinfo = zf.getinfo(f"tables/{table}.jsonl")
                                except KeyError:
                                    continue
                                col_list = tables_info[table]["columns"]
                                
                                # برای mode new_business، id را حذف می‌کنیم تا auto-increment کار کند
                                # و از INSERT IGNORE استفاده می‌کنیم تا از duplicate key errors جلوگیری کنیم
                                insert_col_list = col_list.copy()
                                if mode == "new_business" and "id" in insert_col_list:
                                    insert_col_list.remove("id")
                                
                                placeholders = ", ".join([f":{c}" for c in insert_col_list])
                                columns_sql = ", ".join([f'"{c}"' for c in insert_col_list])  # PostgreSQL uses double quotes
                                
                                # PostgreSQL: ON CONFLICT DO NOTHING (works for any unique constraint)
                                if mode == "new_business":
                                    insert_sql = text(f'INSERT INTO "{table}" ({columns_sql}) VALUES ({placeholders}) ON CONFLICT DO NOTHING')
                                else:
                                    insert_sql = text(f'INSERT INTO "{table}" ({columns_sql}) VALUES ({placeholders})')
                                
                                batch: List[Dict[str, Any]] = []
                                with zf.open(f"tables/{table}.jsonl", "r") as f:
                                    for raw in f:
                                        if not raw:
                                            continue
                                        rec = json.loads(raw.decode("utf-8"))
                                        if "business_id" in rec:
                                            rec["business_id"] = new_business_id
                                        
                                        # برای mode new_business، id را حذف می‌کنیم
                                        if mode == "new_business" and "id" in rec:
                                            del rec["id"]
                                        
                                        params = {c: rec.get(c) for c in insert_col_list}
                                        batch.append(params)
                                        if len(batch) >= 500:
                                            # هر batch در یک transaction جداگانه
                                            max_retries = 3
                                            retry_count = 0
                                            while retry_count < max_retries:
                                                try:
                                                    conn.execute(insert_sql, batch)
                                                    db.commit()
                                                    break  # موفق شد
                                                except Exception as e:
                                                    db.rollback()
                                                    # شروع transaction جدید
                                                    db.begin()
                                                    retry_count += 1
                                                    if retry_count >= max_retries:
                                                        logger.error(f"Error inserting batch into {table} after {max_retries} retries: {e}")
                                                        raise
                                                    logger.warning(f"Error inserting batch into {table}, retry {retry_count}/{max_retries}: {e}")
                                            batch.clear()
                                
                                if batch:
                                    # آخرین batch
                                    max_retries = 3
                                    retry_count = 0
                                    while retry_count < max_retries:
                                        try:
                                            conn.execute(insert_sql, batch)
                                            db.commit()
                                            break  # موفق شد
                                        except Exception as e:
                                            db.rollback()
                                            db.begin()
                                            retry_count += 1
                                            if retry_count >= max_retries:
                                                logger.error(f"Error inserting final batch into {table} after {max_retries} retries: {e}")
                                                raise
                                            logger.warning(f"Error inserting final batch into {table}, retry {retry_count}/{max_retries}: {e}")

                            # فعال کردن دوباره foreign key checks
                            try:
                                conn.execute(text("SET session_replication_role = 'origin'"))  # PostgreSQL equivalent
                            except Exception:
                                pass
                        except Exception as e:
                            db.rollback()
                            # فعال کردن دوباره foreign key checks
                            try:
                                conn.execute(text("SET session_replication_role = 'origin'"))  # PostgreSQL equivalent
                            except Exception:
                                pass
                            raise

                    result_data = {"restored": True, "mode": mode, "business_id": new_business_id}
                    if mode == "new_business":
                        result_data["new_business_id"] = new_business_id
                    jm.succeed(job_id, result_data, "Restore completed")
                except Exception as e:
                    # استخراج error message به صورت مناسب
                    error_msg = None
                    error_code = None
                    error_details = None
                    
                    # بررسی ApiError یا HTTPException
                    from fastapi import HTTPException
                    if isinstance(e, (ApiError, HTTPException)):
                        if hasattr(e, 'detail') and isinstance(e.detail, dict):
                            error_info = e.detail.get("error", {})
                            if isinstance(error_info, dict):
                                error_code = error_info.get("code")
                                error_msg = error_info.get("message")
                                error_details = error_info.get("details")
                        elif isinstance(e.detail, str):
                            error_msg = e.detail
                    
                    # اگر error message پیدا نشد، از str(e) استفاده کن
                    if not error_msg:
                        error_msg = str(e) if e else "Unknown error"
                        if not error_msg or error_msg.strip() == "":
                            error_msg = f"Restore failed: {type(e).__name__}"
                    
                    # ساخت error message مناسب برای frontend
                    if error_code:
                        final_error = f"{error_code}: {error_msg}"
                        if error_details:
                            final_error += f" | Details: {error_details}"
                    else:
                        final_error = error_msg
                    
                    jm.fail(job_id, final_error, "Restore failed")

        background.add_task(task)
        return success_response({"job_id": job_id}, request=request, message="Restore started")
    else:
        # مسیر هم‌زمان قبلی (همان منطق، بدون job)
        # برای اختصار، از مسیر async استفاده کنید؛ این شاخه برای سازگاری باقی می‌ماند
        raise ApiError("SYNC_DISABLED", "Use async_mode=true for restore")


