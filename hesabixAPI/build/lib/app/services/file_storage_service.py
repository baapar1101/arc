import os
import hashlib
import uuid
from typing import Optional, Dict, Any, List
from uuid import UUID
from fastapi import UploadFile, HTTPException
from sqlalchemy.orm import Session
from datetime import datetime, timedelta

from adapters.db.repositories.file_storage_repository import (
    FileStorageRepository, 
    StorageConfigRepository,
    FileVerificationRepository
)
from adapters.db.models.file_storage import FileStorage, StorageConfig


class FileStorageService:
    def __init__(self, db: Session):
        self.db = db
        self.file_repo = FileStorageRepository(db)
        self.config_repo = StorageConfigRepository(db)
        self.verification_repo = FileVerificationRepository(db)

    async def upload_file(
        self,
        file: UploadFile,
        user_id: UUID,
        module_context: str,
        context_id: Optional[UUID] = None,
        developer_data: Optional[Dict] = None,
        is_temporary: bool = False,
        expires_in_days: int = 30,
        storage_config_id: Optional[UUID] = None
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
            
            # محاسبه checksum
            checksum = hashlib.sha256(file_content).hexdigest()

            # ذخیره فایل
            await self._save_file_to_storage(file_content, file_path, storage_config)

            # ذخیره اطلاعات در دیتابیس
            file_storage = await self.file_repo.create_file(
                original_name=file.filename or "unknown",
                stored_name=stored_name,
                file_path=file_path,
                file_size=file_size,
                mime_type=file.content_type or "application/octet-stream",
                storage_type=storage_config.storage_type,
                uploaded_by=user_id,
                module_context=module_context,
                context_id=context_id,
                developer_data=developer_data,
                checksum=checksum,
                is_temporary=is_temporary,
                expires_in_days=expires_in_days,
                storage_config_id=storage_config.id
            )

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

    async def delete_file(self, file_id: UUID) -> bool:
        file_storage = await self.file_repo.get_file_by_id(file_id)
        if not file_storage:
            return False

        # حذف فایل از storage
        await self._delete_file_from_storage(file_storage.file_path, file_storage.storage_type)
        
        # حذف نرم از دیتابیس
        return await self.file_repo.soft_delete_file(file_id)

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
        if storage_type == "local":
            with open(file_path, "rb") as f:
                return f.read()
        elif storage_type == "ftp":
            # TODO: پیاده‌سازی FTP download
            pass
        return b""

    async def _delete_file_from_storage(self, file_path: str, storage_type: str):
        if storage_type == "local":
            if os.path.exists(file_path):
                os.remove(file_path)
        elif storage_type == "ftp":
            # TODO: پیاده‌سازی FTP delete
            pass
