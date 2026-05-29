# Removed __future__ annotations to fix OpenAPI schema generation

from typing import Dict, Any, List
from datetime import datetime, date
from decimal import Decimal
import json
import zipfile
import io

from fastapi import APIRouter, Depends, Request, Query, HTTPException, UploadFile, File, Body, BackgroundTasks
from sqlalchemy.orm import Session
from sqlalchemy import text, inspect
from uuid import UUID

from adapters.db.session import get_db
from adapters.api.v1.schemas import (
    BusinessCreateRequest, BusinessUpdateRequest, BusinessResponse,
    BusinessListResponse, BusinessSummaryResponse, SuccessResponse,
    BusinessType, BusinessField
)
from app.core.responses import success_response, format_datetime_fields, ApiError
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import (
    require_business_management,
    require_business_access,
    require_business_permission_dep,
    require_business_access_dep,
)
from app.core.cache import get_cache
from app.services.business_service import (
    create_business,
    get_business_by_id,
    get_businesses_by_owner,
    get_user_businesses,
    update_business,
    delete_business,
    delete_business_soft,
    get_business_delete_info,
    restore_business,
    get_business_summary,
    get_business_print_settings,
    update_business_print_settings,
    get_business_invoice_share_settings,
    update_business_invoice_share_settings,
    add_business_currency,
    remove_business_currency,
    check_currency_usage_in_documents,
)
from app.services.file_storage_service import FileStorageService
from adapters.db.models.business import Business
from starlette.responses import StreamingResponse
from app.services.job_manager import JobManager
from adapters.api.v1.schema_models.legacy_import import (
    LegacyImportExecuteRequest,
    LegacyImportPreviewRequest,
)


router = APIRouter(prefix="/businesses", tags=["کسب‌وکارها"])


@router.post("", 
    summary="ایجاد کسب و کار جدید", 
    description="ایجاد کسب و کار جدید برای کاربر جاری",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "کسب و کار با موفقیت ایجاد شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "کسب و کار با موفقیت ایجاد شد",
                        "data": {
                            "id": 1,
                            "name": "شرکت نمونه",
                            "business_type": "شرکت",
                            "business_field": "تولیدی",
                            "owner_id": 1,
                            "created_at": "2024-01-01T00:00:00Z"
                        }
                    }
                }
            }
        },
        400: {
            "description": "خطا در اعتبارسنجی داده‌ها"
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        }
    }
)
def create_new_business(
    request: Request,
    business_data: BusinessCreateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> dict:
    """ایجاد کسب و کار جدید"""
    owner_id = ctx.get_user_id()
    business = create_business(db, business_data, owner_id)
    formatted_data = format_datetime_fields(business, request)
    return success_response(formatted_data, request)


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
        "بازرگانی": BusinessField.COMMERCIAL,
        "خدماتی": BusinessField.SERVICE,
        "سایر": BusinessField.OTHER,
    }
    if value_str in persian_values:
        return persian_values[value_str]
    
    # اگر enum name است
    enum_name_to_field = {
        "MANUFACTURING": BusinessField.MANUFACTURING,
        "COMMERCIAL": BusinessField.COMMERCIAL,
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


@router.post("/import-from-backup",
    summary="ایجاد کسب و کار جدید از فایل پشتیبان",
    description="ایجاد کسب و کار جدید از فایل پشتیبان (.hbx). فایل‌های .hs60 در حال حاضر پشتیبانی نمی‌شوند.",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "کسب و کار با موفقیت از فایل پشتیبان ایجاد شد",
        },
        400: {
            "description": "خطا در فایل پشتیبان یا فرمت نامعتبر"
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        }
    }
)
async def import_business_from_backup(
    request: Request,
    file: UploadFile = File(...),
    async_mode: bool = True,
    background: BackgroundTasks = None,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> dict:
    """
    ایجاد کسب و کار جدید از فایل پشتیبان (.hbx)
    
    - پشتیبانی از فایل‌های .hbx (فرمت ZIP با metadata.json و tables/*.jsonl)
    - فایل‌های .hs60 در حال حاضر پشتیبانی نمی‌شوند
    """
    import logging
    logger = logging.getLogger(__name__)
    
    # بررسی پسوند فایل
    filename = file.filename or ""
    file_ext = filename.lower().split('.')[-1] if '.' in filename else ""
    
    # بررسی فایل .hs60 - نمایش خطا
    if file_ext == "hs60":
        raise ApiError(
            "HS60_NOT_SUPPORTED",
            "فرمت فایل .hs60 در حال حاضر پشتیبانی نمی‌شود. این قابلیت در آینده اضافه خواهد شد.",
            http_status=400
        )
    
    # بررسی فایل .hbx
    if file_ext != "hbx":
        raise ApiError(
            "INVALID_FILE_FORMAT",
            "فرمت فایل معتبر نیست. فقط فایل‌های .hbx پشتیبانی می‌شوند.",
            http_status=400
        )
    
    if async_mode:
        jm = JobManager.instance()
        job_id = jm.create("Import business from backup queued")
        
        # خواندن محتوای فایل قبل از شروع background task
        file_bytes: bytes
        try:
            file_bytes = await file.read()
        except Exception as e:
            logger.error(f"Error reading file: {e}")
            raise ApiError("FILE_READ_ERROR", f"خطا در خواندن فایل: {str(e)}", http_status=400)
        
        def task():
            # استفاده از get_db_session برای background task
            from adapters.db.session import get_db_session
            with get_db_session() as db:
                try:
                    jm.start(job_id, "Starting import")
                    jm.update(job_id, 10, "Loading backup file")
                    
                    # بررسی و خواندن فایل ZIP
                    buf = io.BytesIO(file_bytes)
                    try:
                        zf = zipfile.ZipFile(buf, mode="r")
                    except zipfile.BadZipFile:
                        raise ApiError("INVALID_BACKUP", "فایل ZIP معتبر نیست", http_status=400)
                    
                    # خواندن metadata.json
                    try:
                        metadata = json.loads(zf.read("metadata.json").decode("utf-8"))
                    except KeyError:
                        raise ApiError("INVALID_BACKUP", "metadata.json در فایل پشتیبان یافت نشد", http_status=400)
                    
                    jm.update(job_id, 20, "Reading business data")
                    
                    # خواندن اطلاعات کسب‌وکار
                    try:
                        business_rows = []
                        with zf.open("tables/businesses.jsonl", "r") as f:
                            for raw in f:
                                if not raw:
                                    continue
                                business_rows.append(json.loads(raw.decode("utf-8")))
                        
                        if not business_rows:
                            raise ApiError("INVALID_BACKUP", "اطلاعات کسب‌وکار در فایل پشتیبان یافت نشد", http_status=400)
                        
                        original_business = business_rows[0]
                    except KeyError:
                        raise ApiError("INVALID_BACKUP", "tables/businesses.jsonl در فایل پشتیبان یافت نشد", http_status=400)

                    from app.services.business_backup_financial_policy import (
                        compute_backup_checksum,
                        finalize_financial_state_after_restore,
                        guard_new_business_import,
                        register_backup_import,
                        validate_backup_owner,
                    )

                    validate_backup_owner(
                        metadata,
                        ctx.get_user_id(),
                        db=db,
                        backup_business_row=original_business,
                    )
                    backup_checksum = compute_backup_checksum(file_bytes)
                    guard_new_business_import(
                        db,
                        user_id=ctx.get_user_id(),
                        backup_checksum=backup_checksum,
                        import_mode="new_business",
                    )

                    jm.update(job_id, 30, "Creating new business")
                    
                    # تبدیل به BusinessCreateRequest
                    business_create_data = BusinessCreateRequest(
                        name=original_business.get('name', 'کسب‌وکار جدید'),
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
                    
                    # ایجاد کسب‌وکار + ایمپورت جداول در یک تراکنش (مثل /backups/restore)
                    new_business = create_business(
                        db,
                        business_create_data,
                        ctx.get_user_id(),
                        defer_commit=True,
                    )
                    new_business_id = new_business["id"]

                    jm.update(job_id, 40, f"Business created (ID: {new_business_id})")

                    from sqlalchemy import inspect as sa_inspect

                    from adapters.api.v1.business_backups import (
                        _discover_scoped_tables,
                        _sort_tables_for_insert_by_fks,
                        _try_set_session_replication_role_replica,
                        _reset_session_replication_role,
                        _insert_table_from_backup_zip,
                        is_backup_excluded_table,
                    )
                    from app.services.business_backup_schema_compat import (
                        analyze_schema_diff,
                        load_table_column_meta,
                    )

                    tables_info = _discover_scoped_tables(db)
                    target_tables = [
                        t
                        for t in tables_info.keys()
                        if t != "businesses" and not is_backup_excluded_table(t)
                    ]
                    target_tables = _sort_tables_for_insert_by_fks(db.get_bind(), target_tables)

                    conn = db.connection()
                    replica_role_ok = _try_set_session_replication_role_replica(conn)
                    schema_inspector = sa_inspect(db.get_bind())
                    json_cols_cache: dict[str, set[str]] = {}
                    column_meta_cache: dict[str, dict] = {}

                    try:
                        jm.update(job_id, 50, "Importing data")
                        for _t in target_tables:
                            if _t not in column_meta_cache:
                                column_meta_cache[_t] = load_table_column_meta(
                                    schema_inspector, _t, conn
                                )
                        analyze_schema_diff(metadata, tables_info, target_tables, column_meta_cache)

                        for table in target_tables:
                            try:
                                zf.getinfo(f"tables/{table}.jsonl")
                            except KeyError:
                                continue
                            _insert_table_from_backup_zip(
                                conn,
                                zf,
                                table=table,
                                metadata=metadata,
                                tables_info=tables_info,
                                schema_inspector=schema_inspector,
                                new_business_id=new_business_id,
                                mode="new_business",
                                json_cols_cache=json_cols_cache,
                                column_meta_cache=column_meta_cache,
                            )

                        _reset_session_replication_role(conn, replica_role_ok)

                        jm.update(job_id, 90, "Resetting financial state")
                        finalize_financial_state_after_restore(db, new_business_id)
                        register_backup_import(
                            db,
                            user_id=ctx.get_user_id(),
                            backup_checksum=backup_checksum,
                            import_mode="new_business",
                            source_business_id=int(metadata.get("business_id"))
                            if metadata.get("business_id")
                            else None,
                            target_business_id=new_business_id,
                        )
                    except Exception:
                        db.rollback()
                        _reset_session_replication_role(conn, replica_role_ok)
                        raise

                    zf.close()
                    # commit نهایی توسط get_db_session() پس از خروج موفق از task
                    
                    result_data = {
                        "business_id": new_business_id,
                        "business": new_business,
                    }
                    jm.succeed(job_id, result_data, "Import completed")
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
                    
                    # ساخت error message مناسب برای frontend
                    if error_code:
                        final_error = f"{error_code}: {error_msg}"
                        if error_details:
                            final_error += f" | Details: {error_details}"
                    else:
                        final_error = error_msg
                    
                    jm.fail(job_id, final_error, "Import failed")
                    raise
        
        background.add_task(task)
        return success_response({"job_id": job_id}, request=request, message="ایمپورت کسب‌وکار شروع شد")
    else:
        # مسیر هم‌زمان (برای تست - توصیه نمی‌شود برای فایل‌های بزرگ)
        raise ApiError("SYNC_DISABLED", "لطفاً از async_mode=true استفاده کنید", http_status=400)


@router.post(
    "/import-from-legacy-api/preview",
    summary="پیش‌نمایش انتقال از نسخه قدیم (API)",
    description="اعتبارسنجی کلید API و نمایش حجم داده‌های قابل انتقال از حسابیکس نسخه قدیم",
    response_model=SuccessResponse,
)
def preview_import_from_legacy_api(
    request: Request,
    payload: LegacyImportPreviewRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    from app.services.business_service import check_business_creation_permission
    from app.services.legacy_import.preview_service import preview_legacy_import
    can_create, error_message = check_business_creation_permission(db, ctx.get_user_id())
    if not can_create:
        raise ApiError(
            "BUSINESS_CREATION_NOT_ALLOWED",
            error_message or "شما اجازه ایجاد کسب و کار را ندارید",
            http_status=403,
        )
    data = preview_legacy_import(payload.server_url, payload.api_key)
    return success_response(format_datetime_fields(data, request), request, message="پیش‌نمایش انتقال")


@router.post(
    "/import-from-legacy-api",
    summary="ایجاد کسب و کار از نسخه قدیم (API)",
    description="دانلود آرشیو از سرور نسخه قدیم و ایجاد کسب‌وکار جدید در پنل کاربر",
    response_model=SuccessResponse,
)
async def import_business_from_legacy_api(
    request: Request,
    payload: LegacyImportExecuteRequest,
    async_mode: bool = True,
    background: BackgroundTasks = None,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    from app.services.business_service import check_business_creation_permission
    from app.services.legacy_import.importer import LegacyBusinessImporter
    from app.services.legacy_import.preview_service import LegacyImportOptions
    can_create, error_message = check_business_creation_permission(db, ctx.get_user_id())
    if not can_create:
        raise ApiError(
            "BUSINESS_CREATION_NOT_ALLOWED",
            error_message or "شما اجازه ایجاد کسب و کار را ندارید",
            http_status=403,
        )

    if not async_mode:
        raise ApiError(
            "SYNC_DISABLED",
            "لطفاً از async_mode=true استفاده کنید",
            http_status=400,
        )

    opts_schema = payload.options
    options = LegacyImportOptions(
        business_name_override=opts_schema.business_name_override if opts_schema else None,
        business_name_suffix=(opts_schema.business_name_suffix if opts_schema else "") or "",
        import_persons=opts_schema.import_persons if opts_schema else True,
        import_products=opts_schema.import_products if opts_schema else True,
        import_banks=opts_schema.import_banks if opts_schema else True,
        import_warehouses=opts_schema.import_warehouses if opts_schema else True,
        import_documents=opts_schema.import_documents if opts_schema else True,
        import_files=opts_schema.import_files if opts_schema else True,
    )

    jm = JobManager.instance()
    job_id = jm.create("Legacy API import queued")
    owner_id = ctx.get_user_id()
    server_url = payload.server_url
    api_key = payload.api_key

    def task():
        from adapters.db.session import get_db_session

        with get_db_session() as task_db:
            try:
                jm.start(job_id, "Starting legacy import")

                def on_progress(pct: int, msg: str) -> None:
                    jm.update(job_id, pct, msg)

                importer = LegacyBusinessImporter(
                    task_db,
                    owner_id,
                    server_url,
                    api_key,
                    options=options,
                    progress_callback=on_progress,
                )
                result = importer.run()
                jm.succeed(job_id, result, "Legacy import completed")
            except Exception as e:
                error_msg = str(e)
                error_code = None
                if isinstance(e, ApiError) and isinstance(e.detail, dict):
                    err = e.detail.get("error", e.detail)
                    if isinstance(err, dict):
                        error_code = err.get("code")
                        error_msg = err.get("message", error_msg)
                final_error = f"{error_code}: {error_msg}" if error_code else error_msg
                jm.fail(job_id, final_error, "Legacy import failed")
                raise

    background.add_task(task)
    return success_response(
        {"job_id": job_id},
        request=request,
        message="انتقال از نسخه قدیم شروع شد",
    )


@router.post("/list", 
    summary="لیست کسب و کارهای کاربر", 
    description="دریافت لیست کسب و کارهای کاربر جاری با قابلیت فیلتر و جستجو",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "لیست کسب و کارها با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "لیست کسب و کارها دریافت شد",
                        "data": {
                            "items": [
                                {
                                    "id": 1,
                                    "name": "شرکت نمونه",
                                    "business_type": "شرکت",
                                    "business_field": "تولیدی",
                                    "owner_id": 1,
                                    "created_at": "1403/01/01 00:00:00"
                                }
                            ],
                            "pagination": {
                                "total": 1,
                                "page": 1,
                                "per_page": 10,
                                "total_pages": 1,
                                "has_next": False,
                                "has_prev": False
                            }
                        }
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        }
    }
)
def list_user_businesses(
    request: Request,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    take: int = 10,
    skip: int = 0,
    sort_by: str = "created_at",
    sort_desc: bool = True,
    search: str = None
) -> dict:
    """لیست کسب و کارهای کاربر (مالک + عضو)"""
    user_id = ctx.get_user_id()
    query_dict = {
        "take": take,
        "skip": skip,
        "sort_by": sort_by,
        "sort_desc": sort_desc,
        "search": search
    }

    # کش لیست کسب‌وکارهای کاربر
    cache = get_cache()
    cache_key = None

    if cache.enabled:
        import json, hashlib
        key_payload = {
            "user_id": user_id,
            "query": query_dict,
        }
        key_str = json.dumps(key_payload, sort_keys=True, ensure_ascii=False)
        key_hash = hashlib.sha256(key_str.encode("utf-8")).hexdigest()[:16]
        cache_key = f"user_businesses:{key_hash}"
        cached = cache.get(cache_key)
        if cached is not None:
            return success_response(cached, request)

    businesses = get_user_businesses(db, user_id, query_dict)
    formatted_data = format_datetime_fields(businesses, request)

    if cache.enabled and cache_key:
        cache.set(cache_key, formatted_data, ttl=60)
    
    return success_response(formatted_data, request)


@router.get(
    "/{business_id}/print-settings",
    summary="تنظیمات چاپ فاکتورهای کسب‌وکار",
    description="دریافت تنظیمات چاپ فاکتور (لوگو، مهر، پرداخت‌ها، اقساط و متن انتهایی) به‌صورت پیش‌فرض و به تفکیک نوع فاکتور.",
    response_model=SuccessResponse,
)
async def get_business_print_settings_endpoint(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "print")),
) -> dict:
    """دریافت تنظیمات چاپ فاکتورهای یک کسب‌وکار."""
    # بررسی وجود کسب‌وکار (require_business_permission_dep دسترسی را چک کرده است)
    business = db.query(Business).filter(Business.id == business_id).first()
    if not business:
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")

    data = get_business_print_settings(db, business_id)
    return success_response(data, request)


@router.put(
    "/{business_id}/print-settings",
    summary="ویرایش تنظیمات چاپ فاکتورهای کسب‌وکار",
    description="ذخیره تنظیمات چاپ فاکتور (لوگو، مهر، پرداخت‌ها، اقساط و متن انتهایی) به‌صورت پیش‌فرض و به تفکیک نوع فاکتور.",
    response_model=SuccessResponse,
)
async def update_business_print_settings_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any],
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "print")),
) -> dict:
    """ویرایش تنظیمات چاپ فاکتورهای یک کسب‌وکار."""
    # بررسی وجود کسب‌وکار (require_business_permission_dep دسترسی را چک کرده است)
    business = db.query(Business).filter(Business.id == business_id).first()
    if not business:
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")

    updated = update_business_print_settings(db, business_id, payload or {})
    return success_response(updated, request, "تنظیمات چاپ با موفقیت ذخیره شد")


@router.get(
    "/{business_id}/invoice-share-settings",
    summary="تنظیمات پیش‌فرض پرداخت آنلاین لینک عمومی فاکتور",
    description="مقادیر پیش‌فرض برای فعال‌سازی پرداخت آنلاین هنگام ایجاد لینک اشتراک فاکتور جدید.",
    response_model=SuccessResponse,
)
async def get_business_invoice_share_settings_endpoint(
    request: Request,
    business_id: int,
    _ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_access_dep),
) -> dict:
    business = db.query(Business).filter(Business.id == business_id).first()
    if not business:
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")
    data = get_business_invoice_share_settings(db, business_id)
    return success_response(data, request)


@router.put(
    "/{business_id}/invoice-share-settings",
    summary="ذخیرهٔ تنظیمات پیش‌فرض پرداخت آنلاین لینک عمومی فاکتور",
    description="به‌روزرسانی پیش‌فرض‌های پرداخت آنلاین برای لینک‌های اشتراک فاکتور.",
    response_model=SuccessResponse,
)
async def update_business_invoice_share_settings_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "business")),
) -> dict:
    business = db.query(Business).filter(Business.id == business_id).first()
    if not business:
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")
    updated = update_business_invoice_share_settings(db, business_id, payload or {})
    return success_response(updated, request, message="INVOICE_SHARE_SETTINGS_UPDATED")


@router.get("/{business_id}", 
    summary="جزئیات کسب و کار", 
    description="دریافت جزئیات یک کسب و کار خاص",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "جزئیات کسب و کار با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "جزئیات کسب و کار دریافت شد",
                        "data": {
                            "id": 1,
                            "name": "شرکت نمونه",
                            "business_type": "شرکت",
                            "business_field": "تولیدی",
                            "owner_id": 1,
                            "address": "تهران، خیابان ولیعصر",
                            "phone": "02112345678",
                            "created_at": "1403/01/01 00:00:00"
                        }
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        404: {
            "description": "کسب و کار یافت نشد"
        }
    }
)
@router.post("/{business_id}/details", 
    summary="جزئیات کسب و کار", 
    description="دریافت جزئیات یک کسب و کار خاص",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "جزئیات کسب و کار با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "جزئیات کسب و کار دریافت شد",
                        "data": {
                            "id": 1,
                            "name": "شرکت نمونه",
                            "business_type": "شرکت",
                            "business_field": "تولیدی",
                            "owner_id": 1,
                            "address": "تهران، خیابان ولیعصر",
                            "phone": "02112345678",
                            "created_at": "1403/01/01 00:00:00"
                        }
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        404: {
            "description": "کسب و کار یافت نشد"
        }
    }
)
def get_business(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> dict:
    """دریافت جزئیات کسب و کار"""
    owner_id = ctx.get_user_id()
    business = get_business_by_id(db, business_id, owner_id)
    
    if not business:
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")
    
    formatted_data = format_datetime_fields(business, request)
    return success_response(formatted_data, request)


@router.put("/{business_id}", 
    summary="ویرایش کسب و کار", 
    description="ویرایش اطلاعات یک کسب و کار",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "کسب و کار با موفقیت ویرایش شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "کسب و کار با موفقیت ویرایش شد",
                        "data": {
                            "id": 1,
                            "name": "شرکت نمونه ویرایش شده",
                            "business_type": "شرکت",
                            "business_field": "تولیدی",
                            "owner_id": 1,
                            "updated_at": "2024-01-01T12:00:00Z"
                        }
                    }
                }
            }
        },
        400: {
            "description": "خطا در اعتبارسنجی داده‌ها"
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        404: {
            "description": "کسب و کار یافت نشد"
        }
    }
)
@require_business_access("business_id")
def update_business_info(
    request: Request,
    business_id: int,
    business_data: BusinessUpdateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "business")),
) -> dict:
    """ویرایش کسب و کار"""
    owner_id = ctx.get_user_id()
    business = update_business(db, business_id, business_data, owner_id)
    
    if not business:
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")
    
    formatted_data = format_datetime_fields(business, request)
    return success_response(formatted_data, request, "کسب و کار با موفقیت ویرایش شد")


@router.get("/{business_id}/delete-info",
    summary="دریافت اطلاعات حذف کسب و کار",
    description="بررسی و دریافت اطلاعات مرتبط با حذف کسب و کار",
    response_model=SuccessResponse,
)
@require_business_access("business_id")
def get_business_delete_info_endpoint(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """دریافت اطلاعات مرتبط با حذف کسب و کار"""
    owner_id = ctx.get_user_id()
    info = get_business_delete_info(db, business_id, owner_id)
    return success_response(info, request, "اطلاعات حذف کسب و کار")


@router.delete("/{business_id}", 
    summary="حذف کسب و کار", 
    description="حذف نرم یک کسب و کار (30 روز قابل بازیابی)",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "کسب و کار با موفقیت حذف شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "کسب و کار با موفقیت حذف شد. شما 30 روز فرصت دارید آن را بازیابی کنید.",
                        "data": {
                            "business_id": 1,
                            "deleted_at": "2024-01-01T12:00:00Z",
                            "auto_delete_at": "2024-01-31T12:00:00Z",
                            "restore_deadline_days": 30,
                            "backup_created": True
                        }
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        403: {
            "description": "فقط مالک کسب و کار می‌تواند آن را حذف کند"
        },
        404: {
            "description": "کسب و کار یافت نشد"
        },
        409: {
            "description": "نمی‌توان کسب و کار را حذف کرد (محدودیت‌ها وجود دارد)"
        }
    }
)
@require_business_access("business_id")
def delete_business_info(
    request: Request,
    business_id: int,
    deletion_reason: str | None = Body(None, embed=True),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "business")),
) -> dict:
    """
    حذف نرم کسب و کار (Soft Delete)
    - فقط مالک می‌تواند حذف کند
    - قبل از حذف، بکاپ خودکار ایجاد می‌شود
    - اطلاع‌رسانی به مالک ارسال می‌شود
    - کسب و کار 30 روز قابل بازیابی است
    """
    from app.services.notification_service import NotificationService
    
    owner_id = ctx.get_user_id()
    result = delete_business_soft(
        db=db,
        business_id=business_id,
        owner_id=owner_id,
        deletion_reason=deletion_reason,
        requested_by=owner_id
    )
    
    # ارسال اطلاع‌رسانی
    try:
        notification_service = NotificationService(db)
        business = db.query(Business).filter(Business.id == business_id).first()
        if business:
            notification_service.send(
                user_id=owner_id,
                event_key="business.deleted",
                context={
                    "business_name": business.name,
                    "business_id": business_id,
                    "deletion_date": result["deleted_at"],
                    "restore_deadline": result["auto_delete_at"],
                    "restore_days": 30,
                },
                preferred_channels=["email", "telegram", "inapp"]
            )
    except Exception as e:
        import logging
        logger = logging.getLogger(__name__)
        logger.warning(f"Failed to send deletion notification: {e}")
    
    return success_response(
        result, 
        request, 
        "کسب و کار با موفقیت حذف شد. شما 30 روز فرصت دارید آن را بازیابی کنید."
    )


@router.post("/{business_id}/restore",
    summary="بازیابی کسب و کار",
    description="بازیابی کسب و کار حذف شده (فقط در 30 روز اول)",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "کسب و کار با موفقیت بازیابی شد"
        },
        400: {
            "description": "کسب و کار حذف نشده است"
        },
        403: {
            "description": "فقط مالک می‌تواند کسب و کار را بازیابی کند"
        },
        404: {
            "description": "کسب و کار یافت نشد"
        },
        410: {
            "description": "مهلت بازیابی به پایان رسیده است"
        }
    }
)
@require_business_access("business_id")
def restore_business_endpoint(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """بازیابی کسب و کار حذف شده (فقط در 30 روز اول)"""
    from app.services.notification_service import NotificationService
    
    owner_id = ctx.get_user_id()
    result = restore_business(db, business_id, owner_id)
    
    # اطلاع‌رسانی
    try:
        notification_service = NotificationService(db)
        business = db.query(Business).filter(Business.id == business_id).first()
        if business:
            notification_service.send(
                user_id=owner_id,
                event_key="business.restored",
                context={
                    "business_name": business.name,
                    "business_id": business_id,
                },
                preferred_channels=["email", "telegram", "inapp"]
            )
    except Exception as e:
        import logging
        logger = logging.getLogger(__name__)
        logger.warning(f"Failed to send restoration notification: {e}")
    
    return success_response(
        result,
        request,
        "کسب و کار با موفقیت بازیابی شد"
    )


@router.post(
    "/{business_id}/logo",
    summary="آپلود لوگوی کسب‌وکار",
    description="آپلود تصویر لوگوی کسب‌وکار و ذخیره شناسه فایل روی رکورد Business.",
    response_model=SuccessResponse,
)
@require_business_access("business_id")
async def upload_business_logo(
    request: Request,
    business_id: int,
    file: UploadFile = File(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "print")),
) -> dict:
    # بررسی وجود کسب‌وکار
    business = db.query(Business).filter(Business.id == business_id).first()
    if not business:
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")

    storage = FileStorageService(db)
    
    # حذف فایل قدیمی لوگو اگر وجود داشته باشد
    if business.logo_file_id:
        try:
            old_file_id = UUID(str(business.logo_file_id))
            await storage.delete_file(old_file_id)
        except Exception:
            pass  # اگر فایل قدیمی وجود نداشت یا خطا رخ داد، ادامه می‌دهیم
    
    try:
        saved = await storage.upload_file(
            file=file,
            user_id=ctx.get_user_id(),
            module_context="business_logo",
            context_id=None,
            developer_data={"business_id": business_id, "type": "logo"},
            is_temporary=False,
            expires_in_days=3650,
            business_id=business_id,
            check_storage_limit=True,
        )
    except HTTPException as e:
        # اگر خطای محدودیت ذخیره‌سازی باشد، جزئیات را برمی‌گردانیم
        if e.status_code == 400 and isinstance(e.detail, dict) and e.detail.get("error") == "STORAGE_LIMIT_EXCEEDED":
            error_detail = {
                "success": False,
                "error": {
                    "code": "STORAGE_LIMIT_EXCEEDED",
                    "message": e.detail.get("message", "حجم فایل از محدودیت ذخیره‌سازی تجاوز می‌کند"),
                    "total_limit_gb": e.detail.get("total_limit_gb"),
                    "current_usage_gb": e.detail.get("current_usage_gb"),
                    "available_gb": e.detail.get("available_gb"),
                    "required_gb": e.detail.get("required_gb"),
                    "over_usage_gb": e.detail.get("over_usage_gb"),
                }
            }
            raise HTTPException(status_code=400, detail=error_detail)
        raise

    business.logo_file_id = saved.get("file_id")
    db.commit()

    return success_response(
        {
            "logo_file_id": business.logo_file_id,
            "file": saved,
        },
        request,
        "لوگوی کسب‌وکار با موفقیت ذخیره شد",
    )


@router.get(
    "/{business_id}/logo",
    summary="دریافت لوگوی کسب‌وکار",
    description="بازگرداندن تصویر لوگوی کسب‌وکار به‌صورت فایل برای نمایش در UI یا فاکتور.",
)
@require_business_access("business_id")
async def get_business_logo(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "print")),
):
    business = db.query(Business).filter(Business.id == business_id).first()
    if not business or not getattr(business, "logo_file_id", None):
        raise HTTPException(status_code=404, detail="لوگوی کسب و کار تنظیم نشده است")

    storage = FileStorageService(db)
    file_data = await storage.download_file(UUID(str(business.logo_file_id)))

    filename = file_data.get("filename") or "logo"
    return StreamingResponse(
        io.BytesIO(file_data["content"]),
        media_type=file_data.get("mime_type") or "image/png",
        headers={"Content-Disposition": f'inline; filename="{filename}"'},
    )


@router.post(
    "/{business_id}/stamp",
    summary="آپلود مهر/امضای کسب‌وکار",
    description="آپلود تصویر مهر یا امضای رسمی کسب‌وکار و ذخیره شناسه فایل روی رکورد Business.",
    response_model=SuccessResponse,
)
@require_business_access("business_id")
async def upload_business_stamp(
    request: Request,
    business_id: int,
    file: UploadFile = File(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "print")),
) -> dict:
    # بررسی وجود کسب‌وکار
    business = db.query(Business).filter(Business.id == business_id).first()
    if not business:
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")

    storage = FileStorageService(db)
    
    # حذف فایل قدیمی مهر اگر وجود داشته باشد
    if business.stamp_file_id:
        try:
            old_file_id = UUID(str(business.stamp_file_id))
            await storage.delete_file(old_file_id)
        except Exception:
            pass  # اگر فایل قدیمی وجود نداشت یا خطا رخ داد، ادامه می‌دهیم
    
    try:
        saved = await storage.upload_file(
            file=file,
            user_id=ctx.get_user_id(),
            module_context="business_stamp",
            context_id=None,
            developer_data={"business_id": business_id, "type": "stamp"},
            is_temporary=False,
            expires_in_days=3650,
            business_id=business_id,
            check_storage_limit=True,
        )
    except HTTPException as e:
        # اگر خطای محدودیت ذخیره‌سازی باشد، جزئیات را برمی‌گردانیم
        if e.status_code == 400 and isinstance(e.detail, dict) and e.detail.get("error") == "STORAGE_LIMIT_EXCEEDED":
            error_detail = {
                "success": False,
                "error": {
                    "code": "STORAGE_LIMIT_EXCEEDED",
                    "message": e.detail.get("message", "حجم فایل از محدودیت ذخیره‌سازی تجاوز می‌کند"),
                    "total_limit_gb": e.detail.get("total_limit_gb"),
                    "current_usage_gb": e.detail.get("current_usage_gb"),
                    "available_gb": e.detail.get("available_gb"),
                    "required_gb": e.detail.get("required_gb"),
                    "over_usage_gb": e.detail.get("over_usage_gb"),
                }
            }
            raise HTTPException(status_code=400, detail=error_detail)
        raise

    business.stamp_file_id = saved.get("file_id")
    db.commit()

    return success_response(
        {
            "stamp_file_id": business.stamp_file_id,
            "file": saved,
        },
        request,
        "مهر/امضای کسب‌وکار با موفقیت ذخیره شد",
    )


@router.get(
    "/{business_id}/stamp",
    summary="دریافت مهر/امضای کسب‌وکار",
    description="بازگرداندن تصویر مهر یا امضای کسب‌وکار به‌صورت فایل برای نمایش در UI یا فاکتور.",
)
@require_business_access("business_id")
async def get_business_stamp(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "print")),
):
    business = db.query(Business).filter(Business.id == business_id).first()
    if not business or not getattr(business, "stamp_file_id", None):
        raise HTTPException(status_code=404, detail="مهر/امضای کسب و کار تنظیم نشده است")

    storage = FileStorageService(db)
    file_data = await storage.download_file(UUID(str(business.stamp_file_id)))

    filename = file_data.get("filename") or "stamp"
    return StreamingResponse(
        io.BytesIO(file_data["content"]),
        media_type=file_data.get("mime_type") or "image/png",
        headers={"Content-Disposition": f'inline; filename="{filename}"'},
    )


@router.post("/stats", 
    summary="آمار کسب و کارها", 
    description="دریافت آمار کلی کسب و کارهای کاربر",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "آمار کسب و کارها با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "آمار کسب و کارها دریافت شد",
                        "data": {
                            "total_businesses": 5,
                            "by_type": {
                                "شرکت": 2,
                                "مغازه": 1,
                                "فروشگاه": 2
                            },
                            "by_field": {
                                "تولیدی": 3,
                                "خدماتی": 2
                            }
                        }
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        }
    }
)
def get_business_stats(
    request: Request,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> dict:
    """آمار کسب و کارها"""
    owner_id = ctx.get_user_id()
    stats = get_business_summary(db, owner_id)
    return success_response(stats, request)


@router.post(
    "/{business_id}/currencies",
    summary="اضافه کردن ارز جانبی به کسب‌وکار",
    description="اضافه کردن یک ارز به لیست ارزهای قابل استفاده در کسب‌وکار",
    response_model=SuccessResponse,
)
@require_business_access("business_id")
def add_business_currency_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "business")),
) -> dict:
    """اضافه کردن ارز جانبی به کسب‌وکار"""
    currency_id = body.get("currency_id")
    if not currency_id:
        raise HTTPException(status_code=400, detail="currency_id الزامی است")
    
    try:
        currency_id = int(currency_id)
    except (ValueError, TypeError):
        raise HTTPException(status_code=400, detail="currency_id باید یک عدد صحیح باشد")
    
    owner_id = ctx.get_user_id()
    currency_data = add_business_currency(db, business_id, currency_id, owner_id)
    return success_response(currency_data, request, "ارز با موفقیت اضافه شد")


@router.delete(
    "/{business_id}/currencies/{currency_id}",
    summary="حذف ارز جانبی از کسب‌وکار",
    description="حذف یک ارز از لیست ارزهای قابل استفاده در کسب‌وکار (در صورت عدم استفاده در اسناد)",
    response_model=SuccessResponse,
)
@require_business_access("business_id")
def remove_business_currency_endpoint(
    request: Request,
    business_id: int,
    currency_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "business")),
) -> dict:
    """حذف ارز جانبی از کسب‌وکار"""
    owner_id = ctx.get_user_id()
    remove_business_currency(db, business_id, currency_id, owner_id)
    return success_response({"ok": True}, request, "ارز با موفقیت حذف شد")


@router.get(
    "/{business_id}/currencies/{currency_id}/usage-check",
    summary="بررسی استفاده ارز در اسناد",
    description="بررسی اینکه آیا یک ارز در اسناد حسابداری استفاده شده است یا نه",
    response_model=SuccessResponse,
)
@require_business_access("business_id")
def check_currency_usage_endpoint(
    request: Request,
    business_id: int,
    currency_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """بررسی استفاده ارز در اسناد"""
    document_count = check_currency_usage_in_documents(db, business_id, currency_id)
    return success_response({
        "is_used": document_count > 0,
        "document_count": document_count,
        "can_delete": document_count == 0,
    }, request)
