import os
import hashlib
import uuid
from typing import Optional, Dict, Any, List, Literal
from uuid import UUID
from fastapi import UploadFile, HTTPException
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
import logging

from adapters.db.repositories.file_storage_repository import (
    FileStorageRepository,
    StorageConfigRepository,
    FileVerificationRepository,
)
from adapters.db.models.file_storage import FileStorage, StorageConfig

from PIL import Image
import io


class FileStorageService:
    def __init__(self, db: Session):
        self.db = db
        self.file_repo = FileStorageRepository(db)
        self.config_repo = StorageConfigRepository(db)
        self.verification_repo = FileVerificationRepository(db)
        self.logger = logging.getLogger(__name__)

    async def upload_file(
        self,
        file: UploadFile,
        user_id: int | UUID,
        module_context: str,
        context_id: Optional[UUID | str] = None,
        developer_data: Optional[Dict] = None,
        is_temporary: bool = False,
        expires_in_days: int = 30,
        storage_config_id: Optional[UUID] = None,
        business_id: Optional[int] = None,
        check_storage_limit: bool = True,
    ) -> Dict[str, Any]:
        try:
            # دریافت تنظیمات ذخیره‌سازی
            if storage_config_id:
                storage_config = self.db.query(StorageConfig).filter(
                    StorageConfig.id == storage_config_id
                ).first()
            else:
                storage_config = await self.config_repo.get_default_config()
            
            if not storage_config:
                raise HTTPException(status_code=400, detail="No storage configuration found")

            # تولید نام فایل و مسیر
            file_extension = os.path.splitext(file.filename)[1] if file.filename else ""
            stored_name = f"{uuid.uuid4()}{file_extension}"
            
            # تعیین مسیر ذخیره‌سازی
            if storage_config.storage_type == "local":
                file_path = await self._get_local_file_path(stored_name, storage_config.config_data)
            elif storage_config.storage_type == "ftp":
                file_path = await self._get_ftp_file_path(stored_name, storage_config.config_data)
            else:
                raise HTTPException(status_code=400, detail="Unsupported storage type")

            # خواندن محتوای فایل
            file_content = await file.read()
            file_size = len(file_content)
            
            # بررسی محدودیت حجم فایل سیستم
            from app.services.system_settings_service import get_max_file_size_mb
            max_file_size_mb = get_max_file_size_mb(self.db)
            max_file_size_bytes = max_file_size_mb * 1024 * 1024  # تبدیل به بایت
            if file_size > max_file_size_bytes:
                raise HTTPException(
                    status_code=400,
                    detail={
                        "error": "FILE_SIZE_EXCEEDED",
                        "message": f"حجم فایل از حداکثر مجاز ({max_file_size_mb} مگابایت) تجاوز می‌کند",
                        "file_size_mb": round(file_size / (1024 * 1024), 2),
                        "max_file_size_mb": max_file_size_mb
                    }
                )
            
            # بررسی محدودیت ذخیره‌سازی (اگر business_id ارائه شده باشد)
            subscription_id = None
            if business_id and check_storage_limit:
                from app.services.storage_subscription_service import check_storage_limit, get_active_subscriptions
                limit_info = check_storage_limit(self.db, business_id, file_size)
                
                # بررسی اینکه آیا پکیج فعالی وجود دارد یا نه
                if limit_info["total_limit_gb"] <= 0:
                    raise HTTPException(
                        status_code=400,
                        detail={
                            "error": "NO_ACTIVE_STORAGE_PLAN",
                            "message": "هیچ پکیج ذخیره‌سازی فعالی برای این کسب‌وکار وجود ندارد. لطفاً ابتدا یک پکیج ذخیره‌سازی فعال کنید.",
                            "total_limit_gb": 0,
                            "current_usage_gb": limit_info["current_usage_gb"],
                            "available_gb": 0,
                            "required_gb": limit_info["additional_gb"],
                            "over_usage_gb": limit_info["additional_gb"],
                        }
                    )
                
                if limit_info["over_limit"]:
                    # اگر از محدودیت تجاوز کرد، خطا برمی‌گردانیم
                    # Frontend باید از کاربر بپرسد آیا می‌خواهد صورتحساب برای حجم اضافی ایجاد شود
                    raise HTTPException(
                        status_code=400,
                        detail={
                            "error": "STORAGE_LIMIT_EXCEEDED",
                            "message": "حجم فایل از محدودیت ذخیره‌سازی تجاوز می‌کند",
                            "total_limit_gb": limit_info["total_limit_gb"],
                            "current_usage_gb": limit_info["current_usage_gb"],
                            "available_gb": limit_info["available_gb"],
                            "required_gb": limit_info["additional_gb"],
                            "over_usage_gb": limit_info["over_usage_gb"],
                        }
                    )
                
                # دریافت اولین اشتراک فعال برای ثبت
                active_subs = get_active_subscriptions(self.db, business_id)
                if active_subs:
                    subscription_id = active_subs[0]["id"]
            
            # محاسبه checksum
            checksum = hashlib.sha256(file_content).hexdigest()

            # ذخیره فایل
            await self._save_file_to_storage(file_content, file_path, storage_config)

            # تبدیل user_id به int (چون uploaded_by در مدل Integer است)
            if isinstance(user_id, int):
                user_id_int = user_id
            elif isinstance(user_id, UUID):
                # اگر UUID است، نمی‌توانیم مستقیماً به int تبدیل کنیم
                # باید از user_id اصلی استفاده کنیم
                # این حالت نباید اتفاق بیفتد چون ما int می‌فرستیم
                raise ValueError(f"user_id باید int باشد، نه UUID: {user_id}")
            else:
                user_id_int = int(user_id)
            
            # ذخیره اطلاعات در دیتابیس
            file_storage = await self.file_repo.create_file(
                original_name=file.filename or "unknown",
                stored_name=stored_name,
                file_path=file_path,
                file_size=file_size,
                mime_type=file.content_type or "application/octet-stream",
                storage_type=(storage_config.storage_type or "local").lower(),
                uploaded_by=user_id_int,
                module_context=module_context,
                context_id=context_id,
                developer_data=developer_data,
                checksum=checksum,
                is_temporary=is_temporary,
                expires_in_days=expires_in_days,
                storage_config_id=storage_config.id,
                business_id=business_id,
                subscription_id=subscription_id,
            )

            # ثبت تراکنش استفاده
            if business_id:
                from adapters.db.models.storage_plan import StorageUsageTransaction
                usage_gb = file_size / (1024 * 1024 * 1024)
                usage_tx = StorageUsageTransaction(
                    business_id=business_id,
                    file_storage_id=file_storage.id,
                    usage_gb=usage_gb,
                    transaction_type="upload",
                    subscription_id=subscription_id,
                )
                self.db.add(usage_tx)
                self.db.flush()

            # تولید توکن تایید برای فایل‌های موقت
            verification_token = None
            if is_temporary:
                verification_token = str(uuid.uuid4())
                await self.verification_repo.create_verification(
                    file_id=file_storage.id,
                    module_name=module_context,
                    verification_token=verification_token,
                    verification_data=developer_data
                )

            return {
                "file_id": str(file_storage.id),
                "original_name": file_storage.original_name,
                "file_size": file_storage.file_size,
                "mime_type": file_storage.mime_type,
                "is_temporary": file_storage.is_temporary,
                "verification_token": verification_token,
                "expires_at": file_storage.expires_at.isoformat() if file_storage.expires_at else None
            }

        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"File upload failed: {str(e)}")

    async def get_file(self, file_id: UUID) -> Dict[str, Any]:
        file_storage = await self.file_repo.get_file_by_id(file_id)
        if not file_storage:
            raise HTTPException(status_code=404, detail="File not found")

        return {
            "file_id": str(file_storage.id),
            "original_name": file_storage.original_name,
            "file_size": file_storage.file_size,
            "mime_type": file_storage.mime_type,
            "is_temporary": file_storage.is_temporary,
            "is_verified": file_storage.is_verified,
            "created_at": file_storage.created_at.isoformat(),
            "expires_at": file_storage.expires_at.isoformat() if file_storage.expires_at else None
        }

    async def download_file(self, file_id: UUID) -> Dict[str, Any]:
        file_storage = await self.file_repo.get_file_by_id(file_id)
        if not file_storage:
            raise HTTPException(status_code=404, detail="File not found")

        # خواندن فایل از storage
        file_content = await self._read_file_from_storage(file_storage.file_path, file_storage.storage_type)
        
        return {
            "content": file_content,
            "filename": file_storage.original_name,
            "mime_type": file_storage.mime_type
        }

    async def download_image_thumbnail(
        self,
        file_id: UUID,
        size: Literal["small", "medium"] = "small",
    ) -> Dict[str, Any]:
        """
        دانلود thumbnail برای تصاویر.

        - فقط برای فایل‌هایی که mime-type آن‌ها image است استفاده می‌شود.
        - برای جلوگیری از فشار روی سیستم، سایزها محدود و ساده در نظر گرفته شده‌اند.
        """
        file_storage = await self.file_repo.get_file_by_id(file_id)
        if not file_storage:
            raise HTTPException(status_code=404, detail="File not found")

        mime_type = (file_storage.mime_type or "").lower()
        if not mime_type.startswith("image/"):
            # برای غیر تصویر، همان فایل اصلی را برمی‌گردانیم
            return await self.download_file(file_id)

        # خواندن فایل اصلی
        file_content = await self._read_file_from_storage(file_storage.file_path, file_storage.storage_type)

        try:
            # تبدیل بایت‌ها به تصویر PIL
            with Image.open(io.BytesIO(file_content)) as img:
                # تعیین حداکثر ضلع بر اساس سایز
                if size == "medium":
                    max_size = 512
                else:
                    max_size = 256

                img = img.convert("RGB")
                img.thumbnail((max_size, max_size))

                buffer = io.BytesIO()
                # خروجی را همیشه به صورت JPEG با کیفیت متوسط می‌فرستیم
                img.save(buffer, format="JPEG", quality=70, optimize=True)
                buffer.seek(0)

                thumb_bytes = buffer.read()
        except Exception as exc:  # اگر پردازش تصویر شکست خورد، fallback
            # لاگ خطا در logger سراسری سرویس
            self.logger.warning("thumbnail_generation_failed", extra={"error": str(exc)})
            return await self.download_file(file_id)

        return {
            "content": thumb_bytes,
            "filename": file_storage.original_name,
            "mime_type": "image/jpeg",
        }

    async def delete_file(self, file_id: UUID) -> bool:
        file_storage = await self.file_repo.get_file_by_id(file_id)
        if not file_storage:
            return False

        # ثبت تراکنش استفاده (حذف)
        if file_storage.business_id:
            from adapters.db.models.storage_plan import StorageUsageTransaction
            usage_gb = file_storage.file_size / (1024 * 1024 * 1024)
            usage_tx = StorageUsageTransaction(
                business_id=file_storage.business_id,
                file_storage_id=file_storage.id,
                usage_gb=-usage_gb,  # منفی برای حذف
                transaction_type="delete",
                subscription_id=file_storage.subscription_id,
            )
            self.db.add(usage_tx)
            self.db.flush()

        # حذف فایل از storage
        try:
            self.logger.info(
                "file_delete_attempt",
                extra={
                    "file_id": str(file_id),
                    "path": file_storage.file_path,
                    "storage_type": file_storage.storage_type,
                },
            )
        except Exception:
            pass
        await self._delete_file_from_storage(file_storage.file_path, file_storage.storage_type)
        
        # حذف نرم از دیتابیس
        try:
            ok = await self.file_repo.soft_delete_file(file_id)
            try:
                self.logger.info(
                    "file_soft_deleted",
                    extra={"file_id": str(file_id), "ok": ok},
                )
            except Exception:
                pass
            return ok
        except Exception as e:
            try:
                self.logger.exception("file_soft_delete_failed")
            except Exception:
                pass
            raise

    async def verify_file_usage(self, file_id: UUID, verification_data: Dict) -> bool:
        return await self.file_repo.verify_file(file_id, verification_data)

    async def list_files_by_context(
        self, 
        module_context: str, 
        context_id: UUID
    ) -> List[Dict[str, Any]]:
        files = await self.file_repo.get_files_by_context(module_context, context_id)
        return [
            {
                "file_id": str(file.id),
                "original_name": file.original_name,
                "file_size": file.file_size,
                "mime_type": file.mime_type,
                "is_temporary": file.is_temporary,
                "is_verified": file.is_verified,
                "created_at": file.created_at.isoformat()
            }
            for file in files
        ]

    async def cleanup_unverified_files(self) -> Dict[str, Any]:
        unverified_files = await self.file_repo.get_unverified_temporary_files()
        cleaned_count = 0
        
        for file_storage in unverified_files:
            if file_storage.expires_at and file_storage.expires_at < datetime.utcnow():
                await self._delete_file_from_storage(file_storage.file_path, file_storage.storage_type)
                await self.file_repo.soft_delete_file(file_storage.id)
                cleaned_count += 1
        
        return {
            "cleaned_files": cleaned_count,
            "total_unverified": len(unverified_files)
        }

    async def get_storage_statistics(self) -> Dict[str, Any]:
        return await self.file_repo.get_storage_statistics()

    # Helper methods
    async def _get_local_file_path(self, stored_name: str, config_data: Dict) -> str:
        base_path = config_data.get("base_path", "/tmp/hesabix_files")
        os.makedirs(base_path, exist_ok=True)
        return os.path.join(base_path, stored_name)

    async def _get_ftp_file_path(self, stored_name: str, config_data: Dict) -> str:
        # برای FTP، مسیر نسبی را برمی‌گردانیم
        base_path = config_data.get("base_path", "/hesabix_files")
        return f"{base_path}/{stored_name}"

    async def _save_file_to_storage(self, content: bytes, file_path: str, storage_config: StorageConfig):
        if storage_config.storage_type == "local":
            with open(file_path, "wb") as f:
                f.write(content)
        elif storage_config.storage_type == "ftp":
            # TODO: پیاده‌سازی FTP upload
            pass

    async def _read_file_from_storage(self, file_path: str, storage_type: str) -> bytes:
        st = (storage_type or "").lower()
        if st == "local":
            path = file_path
            existed = os.path.exists(path)
            
            # اگر مسیر موجود نیست، یک مسیر جایگزین بر اساس default storage_config امتحان کن
            alt_path = None
            if not existed:
                try:
                    default_cfg = await self.config_repo.get_default_config()
                    if default_cfg and isinstance(default_cfg.config_data, dict):
                        base_path = default_cfg.config_data.get("base_path")
                        if base_path:
                            alt_path = os.path.join(str(base_path), os.path.basename(file_path))
                except Exception:
                    alt_path = None
            
            # خواندن از مسیر اصلی یا جایگزین
            target_path = path
            if not existed and alt_path and os.path.exists(alt_path):
                target_path = alt_path
            
            if not os.path.exists(target_path):
                raise FileNotFoundError(f"File not found: {path} (alternative path also not found: {alt_path})")
            
            try:
                with open(target_path, "rb") as f:
                    return f.read()
            except PermissionError as e:
                raise PermissionError(f"Permission denied reading file: {target_path}") from e
            except Exception as e:
                raise IOError(f"Error reading file: {target_path} - {str(e)}") from e
        elif st == "ftp":
            # TODO: پیاده‌سازی FTP download
            raise NotImplementedError("FTP storage not implemented")
        raise ValueError(f"Unsupported storage type: {storage_type}")

    async def _delete_file_from_storage(self, file_path: str, storage_type: str):
        st = (storage_type or "").lower()
        try:
            self.logger.info(
                "storage_delete_start",
                extra={
                    "storage_type": st,
                    "path": file_path,
                    "exists_before": os.path.exists(file_path),
                },
            )
        except Exception:
            pass
        if st == "local":
            try:
                path = file_path
                existed = os.path.exists(path)
                # اگر مسیر موجود نیست، یک مسیر جایگزین بر اساس default storage_config امتحان کن
                alt_path = None
                if not existed:
                    try:
                        default_cfg = await self.config_repo.get_default_config()
                        if default_cfg and isinstance(default_cfg.config_data, dict):
                            base_path = default_cfg.config_data.get("base_path")
                            if base_path:
                                alt_path = os.path.join(str(base_path), os.path.basename(file_path))
                    except Exception:
                        alt_path = None
                # حذف مسیر اصلی یا جایگزین
                target_path = path
                if not existed and alt_path and os.path.exists(alt_path):
                    target_path = alt_path
                if os.path.exists(target_path):
                    os.remove(file_path)
                    try:
                        self.logger.info(
                            "storage_delete_done",
                            extra={
                                "storage_type": st,
                                "path": target_path,
                                "exists_after": os.path.exists(target_path),
                                "used_alt_path": target_path != path,
                                "alt_path": alt_path,
                            },
                        )
                    except Exception:
                        pass
                else:
                    try:
                        self.logger.warning(
                            "storage_delete_path_not_found",
                            extra={"storage_type": st, "path": path, "alt_path": alt_path},
                        )
                    except Exception:
                        pass
            except Exception as e:
                try:
                    self.logger.exception(
                        "storage_delete_failed",
                        extra={"storage_type": st, "path": file_path},
                    )
                except Exception:
                    pass
        elif st == "ftp":
            # TODO: پیاده‌سازی FTP delete
            try:
                self.logger.warning(
                    "storage_delete_unimplemented",
                    extra={"storage_type": st, "path": file_path},
                )
            except Exception:
                pass
