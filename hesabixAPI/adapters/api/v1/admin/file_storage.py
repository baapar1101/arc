from typing import List, Optional
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File, Request
from sqlalchemy.orm import Session
from sqlalchemy import and_

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_permission
from app.core.responses import success_response
from app.core.responses import ApiError
from app.core.i18n import locale_dependency
from app.services.file_storage_service import FileStorageService
from adapters.db.repositories.file_storage_repository import StorageConfigRepository, FileStorageRepository
from adapters.db.models.user import User
from adapters.db.models.file_storage import StorageConfig
from adapters.api.v1.schema_models.file_storage import (
    StorageConfigCreateRequest,
    StorageConfigUpdateRequest,
    FileUploadRequest,
    FileVerificationRequest,
    FileInfo,
    FileUploadResponse,
    StorageConfigResponse,
    FileStatisticsResponse,
    CleanupResponse
)

router = APIRouter(prefix="/admin/files", tags=["Admin File Management"])


@router.get("/", response_model=dict)
async def list_all_files(
    request: Request,
    page: int = Query(1, ge=1),
    size: int = Query(50, ge=1, le=100),
    module_context: Optional[str] = Query(None),
    is_temporary: Optional[bool] = Query(None),
    is_verified: Optional[bool] = Query(None),
    db: Session = Depends(get_db),
    current_user: AuthContext = Depends(get_current_user),
    translator = Depends(locale_dependency)
):
    """لیست تمام فایل‌ها با فیلتر"""
    try:
        # Check permission
        if not current_user.has_app_permission("admin.file.view"):
            raise ApiError(
                code="FORBIDDEN",
                message=translator.t("FORBIDDEN", "دسترسی غیرمجاز"),
                http_status=403,
                translator=translator
            )
        
        file_repo = FileStorageRepository(db)
        
        # محاسبه offset برای pagination
        offset = (page - 1) * size
        
        # ساخت فیلترها
        filters = []
        if module_context:
            filters.append(FileStorage.module_context == module_context)
        if is_temporary is not None:
            filters.append(FileStorage.is_temporary == is_temporary)
        if is_verified is not None:
            filters.append(FileStorage.is_verified == is_verified)
        
        # اضافه کردن فیلتر حذف نشده
        filters.append(FileStorage.deleted_at.is_(None))
        
        # دریافت فایل‌ها با فیلتر و pagination
        files_query = db.query(FileStorage).filter(and_(*filters))
        total_count = files_query.count()
        
        files = files_query.order_by(FileStorage.created_at.desc()).offset(offset).limit(size).all()
        
        # تبدیل به فرمت مناسب
        files_data = []
        for file in files:
            files_data.append({
                "id": str(file.id),
                "original_name": file.original_name,
                "stored_name": file.stored_name,
                "file_size": file.file_size,
                "mime_type": file.mime_type,
                "storage_type": file.storage_type,
                "module_context": file.module_context,
                "context_id": str(file.context_id) if file.context_id else None,
                "is_temporary": file.is_temporary,
                "is_verified": file.is_verified,
                "is_active": file.is_active,
                "created_at": file.created_at.isoformat(),
                "updated_at": file.updated_at.isoformat(),
                "expires_at": file.expires_at.isoformat() if file.expires_at else None,
                "uploaded_by": file.uploaded_by,
                "checksum": file.checksum
            })
        
        # محاسبه pagination info
        total_pages = (total_count + size - 1) // size
        has_next = page < total_pages
        has_prev = page > 1
        
        data = {
            "files": files_data,
            "pagination": {
                "page": page,
                "size": size,
                "total_count": total_count,
                "total_pages": total_pages,
                "has_next": has_next,
                "has_prev": has_prev
            },
            "filters": {
                "module_context": module_context,
                "is_temporary": is_temporary,
                "is_verified": is_verified
            }
        }
        
        return success_response(data, request)
    except Exception as e:
        raise ApiError(
            code="FILE_LIST_ERROR",
            message=translator.t("FILE_LIST_ERROR", f"خطا در دریافت لیست فایل‌ها: {str(e)}"),
            http_status=500,
            translator=translator
        )


@router.get("/unverified", response_model=dict)
async def get_unverified_files(
    request: Request,
    db: Session = Depends(get_db),
    current_user: AuthContext = Depends(get_current_user),
    translator = Depends(locale_dependency)
):
    """فایل‌های تایید نشده"""
    try:
        file_service = FileStorageService(db)
        unverified_files = await file_service.file_repo.get_unverified_temporary_files()
        
        data = {
            "unverified_files": [
                {
                    "file_id": str(file.id),
                    "original_name": file.original_name,
                    "file_size": file.file_size,
                    "module_context": file.module_context,
                    "created_at": file.created_at.isoformat(),
                    "expires_at": file.expires_at.isoformat() if file.expires_at else None
                }
                for file in unverified_files
            ],
            "count": len(unverified_files)
        }
        
        return success_response(data, request)
    except Exception as e:
        raise ApiError(
            code="UNVERIFIED_FILES_ERROR",
            message=translator.t("UNVERIFIED_FILES_ERROR", f"خطا در دریافت فایل‌های تایید نشده: {str(e)}"),
            http_status=500,
            translator=translator
        )


@router.post("/cleanup-temporary", response_model=dict)
async def cleanup_temporary_files(
    request: Request,
    db: Session = Depends(get_db),
    current_user: AuthContext = Depends(get_current_user),
    translator = Depends(locale_dependency)
):
    """پاکسازی فایل‌های موقت"""
    try:
        file_service = FileStorageService(db)
        cleanup_result = await file_service.cleanup_unverified_files()
        
        data = {
            "message": translator.t("CLEANUP_COMPLETED", "Temporary files cleanup completed"),
            "result": cleanup_result
        }
        
        return success_response(data, request)
    except Exception as e:
        raise ApiError(
            code="CLEANUP_ERROR",
            message=translator.t("CLEANUP_ERROR", f"خطا در پاکسازی فایل‌های موقت: {str(e)}"),
            http_status=500,
            translator=translator
        )


@router.delete("/{file_id}", response_model=dict)
async def force_delete_file(
    file_id: UUID,
    request: Request,
    db: Session = Depends(get_db),
    current_user: AuthContext = Depends(get_current_user),
    translator = Depends(locale_dependency)
):
    """حذف اجباری فایل"""
    try:
        file_service = FileStorageService(db)
        success = await file_service.delete_file(file_id)
        
        if not success:
            raise ApiError(
                code="FILE_NOT_FOUND",
                message=translator.t("FILE_NOT_FOUND", "فایل یافت نشد"),
                http_status=404,
                translator=translator
            )
        
        data = {"message": translator.t("FILE_DELETED_SUCCESS", "File deleted successfully")}
        return success_response(data, request)
    except ApiError:
        raise
    except Exception as e:
        raise ApiError(
            code="DELETE_FILE_ERROR",
            message=translator.t("DELETE_FILE_ERROR", f"خطا در حذف فایل: {str(e)}"),
            http_status=500,
            translator=translator
        )


@router.put("/{file_id}/restore", response_model=dict)
async def restore_file(
    file_id: UUID,
    request: Request,
    db: Session = Depends(get_db),
    current_user: AuthContext = Depends(get_current_user),
    translator = Depends(locale_dependency)
):
    """بازیابی فایل حذف شده"""
    try:
        file_repo = FileStorageRepository(db)
        success = await file_repo.restore_file(file_id)
        
        if not success:
            raise ApiError(
                code="FILE_NOT_FOUND",
                message=translator.t("FILE_NOT_FOUND", "فایل یافت نشد"),
                http_status=404,
                translator=translator
            )
        
        data = {"message": translator.t("FILE_RESTORED_SUCCESS", "File restored successfully")}
        return success_response(data, request)
    except ApiError:
        raise
    except Exception as e:
        raise ApiError(
            code="RESTORE_FILE_ERROR",
            message=translator.t("RESTORE_FILE_ERROR", f"خطا در بازیابی فایل: {str(e)}"),
            http_status=500,
            translator=translator
        )


@router.get("/statistics", response_model=dict)
async def get_file_statistics(
    request: Request,
    db: Session = Depends(get_db),
    current_user: AuthContext = Depends(get_current_user),
    translator = Depends(locale_dependency)
):
    """آمار استفاده از فضای ذخیره‌سازی"""
    try:
        file_service = FileStorageService(db)
        statistics = await file_service.get_storage_statistics()
        
        return success_response(statistics, request)
    except Exception as e:
        raise ApiError(
            code="STATISTICS_ERROR",
            message=translator.t("STATISTICS_ERROR", f"خطا در دریافت آمار: {str(e)}"),
            http_status=500,
            translator=translator
        )


# Storage Configuration Management
@router.get("/storage-configs/", response_model=dict)
async def get_storage_configs(
    request: Request,
    db: Session = Depends(get_db),
    current_user: AuthContext = Depends(get_current_user),
    translator = Depends(locale_dependency)
):
    """لیست تنظیمات ذخیره‌سازی"""
    try:
        # Check permission
        if not current_user.has_app_permission("admin.storage.view"):
            raise ApiError(
                code="FORBIDDEN",
                message=translator.t("FORBIDDEN", "دسترسی غیرمجاز"),
                http_status=403,
                translator=translator
            )
        
        config_repo = StorageConfigRepository(db)
        configs = config_repo.get_all_configs()
        
        data = {
            "configs": [
                {
                    "id": str(config.id),
                    "name": config.name,
                    "storage_type": config.storage_type,
                    "is_default": config.is_default,
                    "is_active": config.is_active,
                    "config_data": config.config_data,
                    "created_at": config.created_at.isoformat()
                }
                for config in configs
            ]
        }
        
        return success_response(data, request)
    except Exception as e:
        raise ApiError(
            code="STORAGE_CONFIGS_ERROR",
            message=translator.t("STORAGE_CONFIGS_ERROR", f"خطا در دریافت تنظیمات ذخیره‌سازی: {str(e)}"),
            http_status=500,
            translator=translator
        )


@router.post("/storage-configs/", response_model=dict)
async def create_storage_config(
    request: Request,
    config_request: StorageConfigCreateRequest,
    db: Session = Depends(get_db),
    current_user: AuthContext = Depends(get_current_user),
    translator = Depends(locale_dependency)
):
    """ایجاد تنظیمات ذخیره‌سازی جدید"""
    try:
        config_repo = StorageConfigRepository(db)
        
        config = await config_repo.create_config(
            name=config_request.name,
            storage_type=config_request.storage_type,
            config_data=config_request.config_data,
            created_by=current_user.get_user_id(),
            is_default=config_request.is_default,
            is_active=config_request.is_active
        )
        
        data = {
            "message": translator.t("STORAGE_CONFIG_CREATED", "Storage configuration created successfully"),
            "config_id": str(config.id)
        }
        
        return success_response(data, request)
    except Exception as e:
        raise ApiError(
            code="CREATE_STORAGE_CONFIG_ERROR",
            message=translator.t("CREATE_STORAGE_CONFIG_ERROR", f"خطا در ایجاد تنظیمات ذخیره‌سازی: {str(e)}"),
            http_status=400,
            translator=translator
        )


@router.put("/storage-configs/{config_id}", response_model=dict)
async def update_storage_config(
    config_id: UUID,
    request: Request,
    config_request: StorageConfigUpdateRequest,
    db: Session = Depends(get_db),
    current_user: AuthContext = Depends(get_current_user),
    translator = Depends(locale_dependency)
):
    """بروزرسانی تنظیمات ذخیره‌سازی"""
    try:
        config_repo = StorageConfigRepository(db)
        
        # TODO: پیاده‌سازی بروزرسانی
        data = {"message": translator.t("STORAGE_CONFIG_UPDATE_NOT_IMPLEMENTED", "Storage configuration update - to be implemented")}
        return success_response(data, request)
    except Exception as e:
        raise ApiError(
            code="UPDATE_STORAGE_CONFIG_ERROR",
            message=translator.t("UPDATE_STORAGE_CONFIG_ERROR", f"خطا در بروزرسانی تنظیمات ذخیره‌سازی: {str(e)}"),
            http_status=500,
            translator=translator
        )


@router.put("/storage-configs/{config_id}/set-default", response_model=dict)
async def set_default_storage_config(
    config_id: UUID,
    request: Request,
    db: Session = Depends(get_db),
    current_user: AuthContext = Depends(get_current_user),
    translator = Depends(locale_dependency)
):
    """تنظیم به عنوان پیش‌فرض"""
    try:
        config_repo = StorageConfigRepository(db)
        success = await config_repo.set_default_config(config_id)
        
        if not success:
            raise ApiError(
                code="STORAGE_CONFIG_NOT_FOUND",
                message=translator.t("STORAGE_CONFIG_NOT_FOUND", "تنظیمات ذخیره‌سازی یافت نشد"),
                http_status=404,
                translator=translator
            )
        
        data = {"message": translator.t("DEFAULT_STORAGE_CONFIG_UPDATED", "Default storage configuration updated successfully")}
        return success_response(data, request)
    except ApiError:
        raise
    except Exception as e:
        raise ApiError(
            code="SET_DEFAULT_STORAGE_CONFIG_ERROR",
            message=translator.t("SET_DEFAULT_STORAGE_CONFIG_ERROR", f"خطا در تنظیم پیش‌فرض: {str(e)}"),
            http_status=500,
            translator=translator
        )


@router.delete("/storage-configs/{config_id}", response_model=dict)
async def delete_storage_config(
    config_id: str,
    request: Request,
    db: Session = Depends(get_db),
    current_user: AuthContext = Depends(get_current_user),
    translator = Depends(locale_dependency)
):
    """حذف تنظیمات ذخیره‌سازی"""
    try:
        # Check permission
        if not current_user.has_app_permission("admin.storage.delete"):
            raise ApiError(
                code="FORBIDDEN",
                message=translator.t("FORBIDDEN", "دسترسی غیرمجاز"),
                http_status=403,
                translator=translator
            )
        
        config_repo = StorageConfigRepository(db)
        
        # بررسی وجود فایل‌ها قبل از حذف
        file_count = config_repo.count_files_by_storage_config(config_id)
        if file_count > 0:
            raise ApiError(
                code="STORAGE_CONFIG_HAS_FILES",
                message=translator.t("STORAGE_CONFIG_HAS_FILES", f"این تنظیمات ذخیره‌سازی دارای {file_count} فایل است و قابل حذف نیست"),
                http_status=400,
                translator=translator
            )
        
        success = config_repo.delete_config(config_id)
        
        if not success:
            raise ApiError(
                code="STORAGE_CONFIG_NOT_FOUND",
                message=translator.t("STORAGE_CONFIG_NOT_FOUND", "تنظیمات ذخیره‌سازی یافت نشد"),
                http_status=404,
                translator=translator
            )
        
        data = {"message": translator.t("STORAGE_CONFIG_DELETED", "Storage configuration deleted successfully")}
        return success_response(data, request)
    except ApiError:
        raise
    except Exception as e:
        raise ApiError(
            code="DELETE_STORAGE_CONFIG_ERROR",
            message=translator.t("DELETE_STORAGE_CONFIG_ERROR", f"خطا در حذف تنظیمات ذخیره‌سازی: {str(e)}"),
            http_status=500,
            translator=translator
        )


@router.post("/storage-configs/{config_id}/test", response_model=dict)
async def test_storage_config(
    config_id: str,
    request: Request,
    db: Session = Depends(get_db),
    current_user: AuthContext = Depends(get_current_user),
    translator = Depends(locale_dependency)
):
    """تست اتصال به storage"""
    try:
        config_repo = StorageConfigRepository(db)
        config = db.query(StorageConfig).filter(StorageConfig.id == config_id).first()
        
        if not config:
            raise ApiError(
                code="STORAGE_CONFIG_NOT_FOUND",
                message=translator.t("STORAGE_CONFIG_NOT_FOUND", "تنظیمات ذخیره‌سازی یافت نشد"),
                http_status=404,
                translator=translator
            )
        
        # تست اتصال بر اساس نوع storage
        test_result = await _test_storage_connection(config)
        
        if test_result["success"]:
            data = {
                "message": translator.t("STORAGE_CONNECTION_SUCCESS", "اتصال به storage موفقیت‌آمیز بود"),
                "test_result": test_result
            }
        else:
            data = {
                "message": translator.t("STORAGE_CONNECTION_FAILED", "اتصال به storage ناموفق بود"),
                "test_result": test_result
            }
        
        return success_response(data, request)
    except ApiError:
        raise
    except Exception as e:
        raise ApiError(
            code="TEST_STORAGE_CONFIG_ERROR",
            message=translator.t("TEST_STORAGE_CONFIG_ERROR", f"خطا در تست اتصال: {str(e)}"),
            http_status=500,
            translator=translator
        )


# Helper function for testing storage connections
async def _test_storage_connection(config: StorageConfig) -> dict:
    """تست اتصال به storage بر اساس نوع آن"""
    import os
    import tempfile
    from datetime import datetime
    
    try:
        if config.storage_type == "local":
            return await _test_local_storage(config)
        elif config.storage_type == "ftp":
            return await _test_ftp_storage(config)
        else:
            return {
                "success": False,
                "error": f"نوع storage پشتیبانی نشده: {config.storage_type}",
                "tested_at": datetime.utcnow().isoformat()
            }
    except Exception as e:
        return {
            "success": False,
            "error": str(e),
            "tested_at": datetime.utcnow().isoformat()
        }


async def _test_local_storage(config: StorageConfig) -> dict:
    """تست اتصال به local storage"""
    import os
    from datetime import datetime
    
    try:
        base_path = config.config_data.get("base_path", "/tmp/hesabix_files")
        
        # بررسی وجود مسیر
        if not os.path.exists(base_path):
            # تلاش برای ایجاد مسیر
            os.makedirs(base_path, exist_ok=True)
        
        # بررسی دسترسی نوشتن
        test_file_path = os.path.join(base_path, f"test_connection_{datetime.utcnow().timestamp()}.txt")
        
        # نوشتن فایل تست
        with open(test_file_path, "w") as f:
            f.write("Test connection file")
        
        # خواندن فایل تست
        with open(test_file_path, "r") as f:
            content = f.read()
        
        # حذف فایل تست
        os.remove(test_file_path)
        
        if content == "Test connection file":
            return {
                "success": True,
                "message": "اتصال به local storage موفقیت‌آمیز بود",
                "storage_type": "local",
                "base_path": base_path,
                "tested_at": datetime.utcnow().isoformat()
            }
        else:
            return {
                "success": False,
                "error": "خطا در خواندن فایل تست",
                "tested_at": datetime.utcnow().isoformat()
            }
            
    except PermissionError:
        return {
            "success": False,
            "error": "دسترسی به مسیر ذخیره‌سازی وجود ندارد",
            "tested_at": datetime.utcnow().isoformat()
        }
    except Exception as e:
        return {
            "success": False,
            "error": f"خطا در تست local storage: {str(e)}",
            "tested_at": datetime.utcnow().isoformat()
        }


async def _test_ftp_storage(config: StorageConfig) -> dict:
    """تست اتصال به FTP storage"""
    import ftplib
    import tempfile
    import os
    from datetime import datetime
    
    try:
        # دریافت تنظیمات FTP
        config_data = config.config_data
        host = config_data.get("host")
        port = int(config_data.get("port", 21))
        username = config_data.get("username")
        password = config_data.get("password")
        directory = config_data.get("directory", "/")
        use_tls = config_data.get("use_tls", False)
        
        # بررسی وجود پارامترهای ضروری
        if not all([host, username, password]):
            return {
                "success": False,
                "error": "پارامترهای ضروری FTP (host, username, password) موجود نیست",
                "storage_type": "ftp",
                "tested_at": datetime.utcnow().isoformat()
            }
        
        # اتصال به FTP
        if use_tls:
            ftp = ftplib.FTP_TLS()
        else:
            ftp = ftplib.FTP()
        
        # تنظیم timeout
        ftp.connect(host, port, timeout=10)
        ftp.login(username, password)
        
        # تغییر به دایرکتوری مورد نظر
        if directory and directory != "/":
            try:
                ftp.cwd(directory)
            except ftplib.error_perm:
                return {
                    "success": False,
                    "error": f"دسترسی به دایرکتوری {directory} وجود ندارد",
                    "storage_type": "ftp",
                    "tested_at": datetime.utcnow().isoformat()
                }
        
        # تست نوشتن فایل
        test_filename = f"test_connection_{datetime.utcnow().timestamp()}.txt"
        test_content = "Test FTP connection file"
        
        # ایجاد فایل موقت
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt') as temp_file:
            temp_file.write(test_content)
            temp_file_path = temp_file.name
        
        try:
            # آپلود فایل
            with open(temp_file_path, 'rb') as file:
                ftp.storbinary(f'STOR {test_filename}', file)
            
            # بررسی وجود فایل
            file_list = []
            ftp.retrlines('LIST', file_list.append)
            file_exists = any(test_filename in line for line in file_list)
            
            if not file_exists:
                return {
                    "success": False,
                    "error": "فایل تست آپلود نشد",
                    "storage_type": "ftp",
                    "tested_at": datetime.utcnow().isoformat()
                }
            
            # حذف فایل تست
            try:
                ftp.delete(test_filename)
            except ftplib.error_perm:
                pass  # اگر نتوانست حذف کند، مهم نیست
            
            # بستن اتصال
            ftp.quit()
            
            return {
                "success": True,
                "message": "اتصال به FTP server موفقیت‌آمیز بود",
                "storage_type": "ftp",
                "host": host,
                "port": port,
                "directory": directory,
                "use_tls": use_tls,
                "tested_at": datetime.utcnow().isoformat()
            }
            
        finally:
            # حذف فایل موقت
            try:
                os.unlink(temp_file_path)
            except:
                pass
        
    except ftplib.error_perm as e:
        return {
            "success": False,
            "error": f"خطا در احراز هویت FTP: {str(e)}",
            "storage_type": "ftp",
            "tested_at": datetime.utcnow().isoformat()
        }
    except ftplib.error_temp as e:
        return {
            "success": False,
            "error": f"خطای موقت FTP: {str(e)}",
            "storage_type": "ftp",
            "tested_at": datetime.utcnow().isoformat()
        }
    except ConnectionRefusedError:
        return {
            "success": False,
            "error": "اتصال به سرور FTP رد شد. بررسی کنید که سرور در حال اجرا باشد",
            "storage_type": "ftp",
            "tested_at": datetime.utcnow().isoformat()
        }
    except Exception as e:
        return {
            "success": False,
            "error": f"خطا در تست FTP storage: {str(e)}",
            "storage_type": "ftp",
            "tested_at": datetime.utcnow().isoformat()
        }
