from typing import Optional, Dict, Any, List
from uuid import UUID
from pydantic import BaseModel, Field
from datetime import datetime


# Request Models
class StorageConfigCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=100, description="نام پیکربندی")
    storage_type: str = Field(..., description="نوع ذخیره‌سازی")
    config_data: Dict[str, Any] = Field(..., description="داده‌های پیکربندی")
    is_default: bool = Field(default=False, description="آیا پیش‌فرض است")
    is_active: bool = Field(default=True, description="آیا فعال است")


class StorageConfigUpdateRequest(BaseModel):
    name: Optional[str] = Field(default=None, min_length=1, max_length=100, description="نام پیکربندی")
    config_data: Optional[Dict[str, Any]] = Field(default=None, description="داده‌های پیکربندی")
    is_active: Optional[bool] = Field(default=None, description="آیا فعال است")


class FileUploadRequest(BaseModel):
    module_context: str = Field(..., description="زمینه ماژول")
    context_id: Optional[UUID] = Field(default=None, description="شناسه زمینه")
    developer_data: Optional[Dict[str, Any]] = Field(default=None, description="داده‌های توسعه‌دهنده")
    is_temporary: bool = Field(default=False, description="آیا فایل موقت است")
    expires_in_days: int = Field(default=30, ge=1, le=365, description="تعداد روزهای انقضا")


class FileVerificationRequest(BaseModel):
    verification_data: Dict[str, Any] = Field(..., description="داده‌های تایید")


# Response Models
class FileInfo(BaseModel):
    file_id: str = Field(..., description="شناسه فایل")
    original_name: str = Field(..., description="نام اصلی فایل")
    file_size: int = Field(..., description="حجم فایل")
    mime_type: str = Field(..., description="نوع فایل")
    is_temporary: bool = Field(..., description="آیا موقت است")
    is_verified: bool = Field(..., description="آیا تایید شده است")
    created_at: str = Field(..., description="تاریخ ایجاد")
    expires_at: Optional[str] = Field(default=None, description="تاریخ انقضا")

    class Config:
        from_attributes = True


class FileUploadResponse(BaseModel):
    file_id: str = Field(..., description="شناسه فایل")
    original_name: str = Field(..., description="نام اصلی فایل")
    file_size: int = Field(..., description="حجم فایل")
    mime_type: str = Field(..., description="نوع فایل")
    is_temporary: bool = Field(..., description="آیا موقت است")
    verification_token: Optional[str] = Field(default=None, description="توکن تایید")
    expires_at: Optional[str] = Field(default=None, description="تاریخ انقضا")


class StorageConfigResponse(BaseModel):
    id: str = Field(..., description="شناسه پیکربندی")
    name: str = Field(..., description="نام پیکربندی")
    storage_type: str = Field(..., description="نوع ذخیره‌سازی")
    is_default: bool = Field(..., description="آیا پیش‌فرض است")
    is_active: bool = Field(..., description="آیا فعال است")
    created_at: str = Field(..., description="تاریخ ایجاد")

    class Config:
        from_attributes = True


class FileStatisticsResponse(BaseModel):
    total_files: int = Field(..., description="کل فایل‌ها")
    total_size: int = Field(..., description="حجم کل")
    temporary_files: int = Field(..., description="فایل‌های موقت")
    unverified_files: int = Field(..., description="فایل‌های تایید نشده")


class CleanupResponse(BaseModel):
    cleaned_files: int = Field(..., description="تعداد فایل‌های پاکسازی شده")
    total_unverified: int = Field(..., description="کل فایل‌های تایید نشده")
