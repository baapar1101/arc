"""
Schema models مشترک برای کل API

این ماژول شامل schema های مشترکی است که در سراسر API استفاده می‌شوند.
"""
from typing import Optional, Any, Dict, List, Generic, TypeVar
from pydantic import BaseModel, Field
from enum import Enum


T = TypeVar('T')


class SuccessResponse(BaseModel, Generic[T]):
    """
    پاسخ استاندارد موفق
    
    تمام endpoint های API این فرمت را برای پاسخ‌های موفق استفاده می‌کنند.
    """
    success: bool = Field(
        default=True,
        description="وضعیت موفقیت عملیات - همیشه true در پاسخ‌های موفق"
    )
    message: Optional[str] = Field(
        None,
        description="پیام توضیحی درباره عملیات انجام شده",
        example="عملیات با موفقیت انجام شد"
    )
    data: Optional[T] = Field(
        None,
        description="داده‌های بازگشتی - نوع آن بسته به endpoint متفاوت است"
    )
    
    class Config:
        json_schema_extra = {
            "example": {
                "success": True,
                "message": "عملیات با موفقیت انجام شد",
                "data": {
                    "id": 123,
                    "name": "نمونه"
                }
            }
        }


class ErrorCode(str, Enum):
    """کدهای خطای استاندارد API"""
    
    # خطاهای احراز هویت (401)
    UNAUTHORIZED = "UNAUTHORIZED"
    INVALID_API_KEY = "INVALID_API_KEY"
    EXPIRED_API_KEY = "EXPIRED_API_KEY"
    INVALID_CREDENTIALS = "INVALID_CREDENTIALS"
    
    # خطاهای دسترسی (403)
    FORBIDDEN = "FORBIDDEN"
    INSUFFICIENT_PERMISSIONS = "INSUFFICIENT_PERMISSIONS"
    BUSINESS_ACCESS_DENIED = "BUSINESS_ACCESS_DENIED"
    
    # خطاهای یافت نشدن (404)
    NOT_FOUND = "NOT_FOUND"
    RESOURCE_NOT_FOUND = "RESOURCE_NOT_FOUND"
    DOCUMENT_NOT_FOUND = "DOCUMENT_NOT_FOUND"
    USER_NOT_FOUND = "USER_NOT_FOUND"
    BUSINESS_NOT_FOUND = "BUSINESS_NOT_FOUND"
    
    # خطاهای اعتبارسنجی (400)
    VALIDATION_ERROR = "VALIDATION_ERROR"
    INVALID_INPUT = "INVALID_INPUT"
    INVALID_PARAMETERS = "INVALID_PARAMETERS"
    INVALID_DATE_RANGE = "INVALID_DATE_RANGE"
    INVALID_AMOUNT = "INVALID_AMOUNT"
    
    # خطاهای منطق کسب‌وکار (400)
    DUPLICATE_ENTRY = "DUPLICATE_ENTRY"
    INSUFFICIENT_BALANCE = "INSUFFICIENT_BALANCE"
    INSUFFICIENT_INVENTORY = "INSUFFICIENT_INVENTORY"
    DOCUMENT_LOCKED = "DOCUMENT_LOCKED"
    DOCUMENT_CONFIRMED = "DOCUMENT_CONFIRMED"
    HAS_DEPENDENCIES = "HAS_DEPENDENCIES"
    
    # خطاهای محدودیت (429)
    RATE_LIMIT_EXCEEDED = "RATE_LIMIT_EXCEEDED"
    QUOTA_EXCEEDED = "QUOTA_EXCEEDED"
    STORAGE_LIMIT_EXCEEDED = "STORAGE_LIMIT_EXCEEDED"
    
    # خطاهای سرور (500)
    INTERNAL_SERVER_ERROR = "INTERNAL_SERVER_ERROR"
    DATABASE_ERROR = "DATABASE_ERROR"
    EXTERNAL_SERVICE_ERROR = "EXTERNAL_SERVICE_ERROR"
    
    # خطاهای سرویس (503)
    SERVICE_UNAVAILABLE = "SERVICE_UNAVAILABLE"
    MAINTENANCE_MODE = "MAINTENANCE_MODE"


class ErrorDetail(BaseModel):
    """جزئیات خطا"""
    field: Optional[str] = Field(
        None,
        description="نام فیلد مرتبط با خطا (در صورت وجود)",
        example="email"
    )
    message: str = Field(
        ...,
        description="پیام خطا",
        example="فرمت ایمیل نامعتبر است"
    )
    code: Optional[str] = Field(
        None,
        description="کد خطای خاص",
        example="INVALID_EMAIL_FORMAT"
    )


class ErrorResponse(BaseModel):
    """
    پاسخ استاندارد خطا
    
    تمام خطاهای API در این فرمت برگردانده می‌شوند.
    """
    success: bool = Field(
        default=False,
        description="وضعیت موفقیت - همیشه false در پاسخ‌های خطا"
    )
    error_code: str = Field(
        ...,
        description="کد خطا - برای شناسایی نوع خطا",
        example="VALIDATION_ERROR"
    )
    message: str = Field(
        ...,
        description="پیام خطا به زبان فارسی",
        example="داده‌های ورودی نامعتبر است"
    )
    details: Optional[List[ErrorDetail]] = Field(
        None,
        description="جزئیات بیشتر درباره خطا (مخصوص خطاهای اعتبارسنجی)"
    )
    timestamp: Optional[str] = Field(
        None,
        description="زمان وقوع خطا",
        example="2024-01-15T10:30:00Z"
    )
    path: Optional[str] = Field(
        None,
        description="مسیر endpoint که خطا در آن رخ داده",
        example="/api/v1/users"
    )
    
    class Config:
        json_schema_extra = {
            "examples": [
                {
                    "summary": "خطای اعتبارسنجی",
                    "value": {
                        "success": False,
                        "error_code": "VALIDATION_ERROR",
                        "message": "خطا در اعتبارسنجی داده‌های ورودی",
                        "details": [
                            {
                                "field": "email",
                                "message": "فرمت ایمیل نامعتبر است",
                                "code": "INVALID_EMAIL_FORMAT"
                            }
                        ]
                    }
                },
                {
                    "summary": "خطای احراز هویت",
                    "value": {
                        "success": False,
                        "error_code": "UNAUTHORIZED",
                        "message": "کلید API نامعتبر یا منقضی شده است"
                    }
                },
                {
                    "summary": "خطای عدم دسترسی",
                    "value": {
                        "success": False,
                        "error_code": "FORBIDDEN",
                        "message": "شما مجوز دسترسی به این منبع را ندارید"
                    }
                },
                {
                    "summary": "خطای یافت نشدن",
                    "value": {
                        "success": False,
                        "error_code": "NOT_FOUND",
                        "message": "منبع درخواستی یافت نشد"
                    }
                }
            ]
        }


class PaginationMeta(BaseModel):
    """متادیتای صفحه‌بندی"""
    total_count: int = Field(
        ...,
        description="تعداد کل رکوردها",
        example=100
    )
    page: Optional[int] = Field(
        None,
        description="شماره صفحه فعلی (شروع از 1)",
        example=1
    )
    per_page: Optional[int] = Field(
        None,
        description="تعداد رکورد در هر صفحه",
        example=20
    )
    total_pages: Optional[int] = Field(
        None,
        description="تعداد کل صفحات",
        example=5
    )
    has_more: bool = Field(
        ...,
        description="آیا صفحه بعدی وجود دارد؟",
        example=True
    )
    has_previous: Optional[bool] = Field(
        None,
        description="آیا صفحه قبلی وجود دارد؟",
        example=False
    )


class PaginatedResponse(BaseModel, Generic[T]):
    """پاسخ صفحه‌بندی شده"""
    items: List[T] = Field(
        ...,
        description="لیست آیتم‌های صفحه فعلی"
    )
    meta: PaginationMeta = Field(
        ...,
        description="متادیتای صفحه‌بندی"
    )
    
    # برای سازگاری با قبل
    total_count: Optional[int] = Field(
        None,
        description="[منسوخ] از meta.total_count استفاده کنید"
    )
    has_more: Optional[bool] = Field(
        None,
        description="[منسوخ] از meta.has_more استفاده کنید"
    )


class BulkOperationResult(BaseModel):
    """نتیجه عملیات گروهی"""
    total: int = Field(
        ...,
        description="تعداد کل آیتم‌های پردازش شده",
        example=10
    )
    successful: int = Field(
        ...,
        description="تعداد عملیات موفق",
        example=8
    )
    failed: int = Field(
        ...,
        description="تعداد عملیات ناموفق",
        example=2
    )
    errors: Optional[List[Dict[str, Any]]] = Field(
        None,
        description="لیست خطاهای رخ داده"
    )
    
    class Config:
        json_schema_extra = {
            "example": {
                "total": 10,
                "successful": 8,
                "failed": 2,
                "errors": [
                    {
                        "item_id": 5,
                        "error": "موجودی کافی نیست"
                    },
                    {
                        "item_id": 7,
                        "error": "محصول یافت نشد"
                    }
                ]
            }
        }


class HealthCheckResponse(BaseModel):
    """پاسخ بررسی سلامت سرویس"""
    status: str = Field(
        ...,
        description="وضعیت سرویس: healthy, degraded, unhealthy",
        example="healthy"
    )
    version: str = Field(
        ...,
        description="نسخه API",
        example="1.0.0"
    )
    timestamp: str = Field(
        ...,
        description="زمان بررسی",
        example="2024-01-15T10:30:00Z"
    )
    services: Optional[Dict[str, str]] = Field(
        None,
        description="وضعیت سرویس‌های وابسته (database, cache, etc)"
    )
    
    class Config:
        json_schema_extra = {
            "example": {
                "status": "healthy",
                "version": "1.0.0",
                "timestamp": "2024-01-15T10:30:00Z",
                "services": {
                    "database": "healthy",
                    "cache": "healthy",
                    "storage": "healthy"
                }
            }
        }


class FileUploadResponse(BaseModel):
    """پاسخ آپلود فایل"""
    file_id: str = Field(
        ...,
        description="شناسه یکتای فایل (UUID)",
        example="123e4567-e89b-12d3-a456-426614174000"
    )
    filename: str = Field(
        ...,
        description="نام فایل",
        example="document.pdf"
    )
    file_size: int = Field(
        ...,
        description="حجم فایل (بایت)",
        example=1048576
    )
    mime_type: str = Field(
        ...,
        description="نوع MIME فایل",
        example="application/pdf"
    )
    url: Optional[str] = Field(
        None,
        description="URL دسترسی به فایل",
        example="https://files.hesabix.ir/123e4567.pdf"
    )
    
    class Config:
        json_schema_extra = {
            "example": {
                "file_id": "123e4567-e89b-12d3-a456-426614174000",
                "filename": "invoice.pdf",
                "file_size": 524288,
                "mime_type": "application/pdf",
                "url": "https://files.hesabix.ir/123e4567.pdf"
            }
        }


class ExportResponse(BaseModel):
    """پاسخ درخواست خروجی (Excel/PDF)"""
    file_url: Optional[str] = Field(
        None,
        description="URL دانلود فایل (در صورت ذخیره‌سازی)",
        example="https://files.hesabix.ir/exports/report.xlsx"
    )
    filename: str = Field(
        ...,
        description="نام فایل پیشنهادی",
        example="sales_report_20240115.xlsx"
    )
    file_size: Optional[int] = Field(
        None,
        description="حجم فایل (بایت)",
        example=2097152
    )
    expires_at: Optional[str] = Field(
        None,
        description="تاریخ انقضای لینک دانلود",
        example="2024-01-16T10:30:00Z"
    )


# Common HTTP Status Responses
COMMON_RESPONSES = {
    400: {
        "description": "خطا در اعتبارسنجی داده‌های ورودی",
        "model": ErrorResponse,
        "content": {
            "application/json": {
                "example": {
                    "success": False,
                    "error_code": "VALIDATION_ERROR",
                    "message": "داده‌های ورودی نامعتبر است"
                }
            }
        }
    },
    401: {
        "description": "احراز هویت نشده - کلید API نامعتبر یا منقضی شده",
        "model": ErrorResponse,
        "content": {
            "application/json": {
                "example": {
                    "success": False,
                    "error_code": "UNAUTHORIZED",
                    "message": "کلید API نامعتبر یا منقضی شده است"
                }
            }
        }
    },
    403: {
        "description": "عدم مجوز دسترسی به این منبع",
        "model": ErrorResponse,
        "content": {
            "application/json": {
                "example": {
                    "success": False,
                    "error_code": "FORBIDDEN",
                    "message": "شما مجوز دسترسی به این منبع را ندارید"
                }
            }
        }
    },
    404: {
        "description": "منبع درخواستی یافت نشد",
        "model": ErrorResponse,
        "content": {
            "application/json": {
                "example": {
                    "success": False,
                    "error_code": "NOT_FOUND",
                    "message": "منبع درخواستی یافت نشد"
                }
            }
        }
    },
    429: {
        "description": "تعداد درخواست‌ها بیش از حد مجاز - Rate limit exceeded",
        "model": ErrorResponse,
        "content": {
            "application/json": {
                "example": {
                    "success": False,
                    "error_code": "RATE_LIMIT_EXCEEDED",
                    "message": "تعداد درخواست‌های شما بیش از حد مجاز است"
                }
            }
        }
    },
    500: {
        "description": "خطای داخلی سرور",
        "model": ErrorResponse,
        "content": {
            "application/json": {
                "example": {
                    "success": False,
                    "error_code": "INTERNAL_SERVER_ERROR",
                    "message": "خطای داخلی سرور رخ داده است"
                }
            }
        }
    },
    503: {
        "description": "سرویس در دسترس نیست - Maintenance Mode",
        "model": ErrorResponse,
        "content": {
            "application/json": {
                "example": {
                    "success": False,
                    "error_code": "SERVICE_UNAVAILABLE",
                    "message": "سرویس در حال حاضر در دسترس نیست"
                }
            }
        }
    }
}


