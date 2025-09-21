from typing import List, Optional
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user
from app.core.permissions import require_permission
from app.core.responses import success_response
from app.core.error_handlers import ApiError
from app.core.i18n import locale_dependency
from app.services.file_storage_service import FileStorageService
from adapters.db.repositories.file_storage_repository import StorageConfigRepository, FileStorageRepository
from adapters.db.models.user import User
from adapters.api.v1.schemas.file_storage import (
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
    current_user: User = Depends(require_permission("admin.file.view")),
    translator = Depends(locale_dependency)
):
    """لیست تمام فایل‌ها با فیلتر"""
    try:
        file_service = FileStorageService(db)
        
        # TODO: پیاده‌سازی pagination و فیلترها
        statistics = await file_service.get_storage_statistics()
        
        data = {
            "statistics": statistics,
            "message": translator.t("FILE_LIST_NOT_IMPLEMENTED", "File list endpoint - to be implemented")
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
    current_user: User = Depends(require_permission("admin.file.view")),
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
    current_user: User = Depends(require_permission("admin.file.cleanup")),
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
    current_user: User = Depends(require_permission("admin.file.delete")),
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
    current_user: User = Depends(require_permission("admin.file.restore")),
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
    current_user: User = Depends(require_permission("admin.file.view")),
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
    current_user: User = Depends(require_permission("admin.storage.view")),
    translator = Depends(locale_dependency)
):
    """لیست تنظیمات ذخیره‌سازی"""
    try:
        config_repo = StorageConfigRepository(db)
        configs = await config_repo.get_all_configs()
        
        data = {
            "configs": [
                {
                    "id": str(config.id),
                    "name": config.name,
                    "storage_type": config.storage_type,
                    "is_default": config.is_default,
                    "is_active": config.is_active,
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
    current_user: User = Depends(require_permission("admin.storage.create")),
    translator = Depends(locale_dependency)
):
    """ایجاد تنظیمات ذخیره‌سازی جدید"""
    try:
        config_repo = StorageConfigRepository(db)
        
        config = await config_repo.create_config(
            name=config_request.name,
            storage_type=config_request.storage_type,
            config_data=config_request.config_data,
            created_by=current_user.id,
            is_default=config_request.is_default
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
    current_user: User = Depends(require_permission("admin.storage.update")),
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
    current_user: User = Depends(require_permission("admin.storage.update")),
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
    config_id: UUID,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("admin.storage.delete")),
    translator = Depends(locale_dependency)
):
    """حذف تنظیمات ذخیره‌سازی"""
    try:
        config_repo = StorageConfigRepository(db)
        success = await config_repo.delete_config(config_id)
        
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
    config_id: UUID,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("admin.storage.test")),
    translator = Depends(locale_dependency)
):
    """تست اتصال به storage"""
    try:
        # TODO: پیاده‌سازی تست اتصال
        data = {"message": translator.t("STORAGE_CONNECTION_TEST_NOT_IMPLEMENTED", "Storage connection test - to be implemented")}
        return success_response(data, request)
    except Exception as e:
        raise ApiError(
            code="TEST_STORAGE_CONFIG_ERROR",
            message=translator.t("TEST_STORAGE_CONFIG_ERROR", f"خطا در تست اتصال: {str(e)}"),
            http_status=500,
            translator=translator
        )
