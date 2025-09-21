from typing import List, Optional, Dict, Any
from uuid import UUID
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_, desc, func
from datetime import datetime, timedelta

from adapters.db.models.file_storage import FileStorage, StorageConfig, FileVerification
from adapters.db.repositories.base import BaseRepository


class FileStorageRepository(BaseRepository[FileStorage]):
    def __init__(self, db: Session):
        super().__init__(FileStorage, db)

    async def create_file(
        self,
        original_name: str,
        stored_name: str,
        file_path: str,
        file_size: int,
        mime_type: str,
        storage_type: str,
        uploaded_by: UUID,
        module_context: str,
        context_id: Optional[UUID] = None,
        developer_data: Optional[Dict] = None,
        checksum: Optional[str] = None,
        is_temporary: bool = False,
        expires_in_days: int = 30,
        storage_config_id: Optional[UUID] = None
    ) -> FileStorage:
        expires_at = None
        if is_temporary:
            expires_at = datetime.utcnow() + timedelta(days=expires_in_days)

        file_storage = FileStorage(
            original_name=original_name,
            stored_name=stored_name,
            file_path=file_path,
            file_size=file_size,
            mime_type=mime_type,
            storage_type=storage_type,
            storage_config_id=storage_config_id,
            uploaded_by=uploaded_by,
            module_context=module_context,
            context_id=context_id,
            developer_data=developer_data,
            checksum=checksum,
            is_temporary=is_temporary,
            expires_at=expires_at
        )
        
        self.db.add(file_storage)
        self.db.commit()
        self.db.refresh(file_storage)
        return file_storage

    async def get_file_by_id(self, file_id: UUID) -> Optional[FileStorage]:
        return self.db.query(FileStorage).filter(
            and_(
                FileStorage.id == file_id,
                FileStorage.deleted_at.is_(None)
            )
        ).first()

    async def get_files_by_context(
        self, 
        module_context: str, 
        context_id: UUID
    ) -> List[FileStorage]:
        return self.db.query(FileStorage).filter(
            and_(
                FileStorage.module_context == module_context,
                FileStorage.context_id == context_id,
                FileStorage.deleted_at.is_(None),
                FileStorage.is_active == True
            )
        ).order_by(desc(FileStorage.created_at)).all()

    async def get_user_files(
        self, 
        user_id: UUID, 
        limit: int = 50, 
        offset: int = 0
    ) -> List[FileStorage]:
        return self.db.query(FileStorage).filter(
            and_(
                FileStorage.uploaded_by == user_id,
                FileStorage.deleted_at.is_(None)
            )
        ).order_by(desc(FileStorage.created_at)).offset(offset).limit(limit).all()

    async def get_unverified_temporary_files(self) -> List[FileStorage]:
        return self.db.query(FileStorage).filter(
            and_(
                FileStorage.is_temporary == True,
                FileStorage.is_verified == False,
                FileStorage.deleted_at.is_(None),
                FileStorage.is_active == True
            )
        ).all()

    async def get_expired_temporary_files(self) -> List[FileStorage]:
        return self.db.query(FileStorage).filter(
            and_(
                FileStorage.is_temporary == True,
                FileStorage.expires_at < datetime.utcnow(),
                FileStorage.deleted_at.is_(None)
            )
        ).all()

    async def verify_file(self, file_id: UUID, verification_data: Dict) -> bool:
        file_storage = await self.get_file_by_id(file_id)
        if not file_storage:
            return False
        
        file_storage.is_verified = True
        file_storage.last_verified_at = datetime.utcnow()
        file_storage.developer_data = {**(file_storage.developer_data or {}), **verification_data}
        
        self.db.commit()
        return True

    async def soft_delete_file(self, file_id: UUID) -> bool:
        file_storage = await self.get_file_by_id(file_id)
        if not file_storage:
            return False
        
        file_storage.deleted_at = datetime.utcnow()
        file_storage.is_active = False
        
        self.db.commit()
        return True

    async def restore_file(self, file_id: UUID) -> bool:
        file_storage = self.db.query(FileStorage).filter(FileStorage.id == file_id).first()
        if not file_storage:
            return False
        
        file_storage.deleted_at = None
        file_storage.is_active = True
        
        self.db.commit()
        return True

    async def get_storage_statistics(self) -> Dict[str, Any]:
        total_files = self.db.query(FileStorage).filter(
            FileStorage.deleted_at.is_(None)
        ).count()
        
        total_size = self.db.query(func.sum(FileStorage.file_size)).filter(
            FileStorage.deleted_at.is_(None)
        ).scalar() or 0
        
        temporary_files = self.db.query(FileStorage).filter(
            and_(
                FileStorage.is_temporary == True,
                FileStorage.deleted_at.is_(None)
            )
        ).count()
        
        unverified_files = self.db.query(FileStorage).filter(
            and_(
                FileStorage.is_temporary == True,
                FileStorage.is_verified == False,
                FileStorage.deleted_at.is_(None)
            )
        ).count()
        
        return {
            "total_files": total_files,
            "total_size": total_size,
            "temporary_files": temporary_files,
            "unverified_files": unverified_files
        }


class StorageConfigRepository(BaseRepository[StorageConfig]):
    def __init__(self, db: Session):
        super().__init__(StorageConfig, db)

    async def create_config(
        self,
        name: str,
        storage_type: str,
        config_data: Dict,
        created_by: UUID,
        is_default: bool = False
    ) -> StorageConfig:
        # اگر این config به عنوان پیش‌فرض تنظیم می‌شود، بقیه را غیرفعال کن
        if is_default:
            await self.clear_default_configs()
        
        storage_config = StorageConfig(
            name=name,
            storage_type=storage_type,
            config_data=config_data,
            created_by=created_by,
            is_default=is_default
        )
        
        self.db.add(storage_config)
        self.db.commit()
        self.db.refresh(storage_config)
        return storage_config

    async def get_default_config(self) -> Optional[StorageConfig]:
        return self.db.query(StorageConfig).filter(
            and_(
                StorageConfig.is_default == True,
                StorageConfig.is_active == True
            )
        ).first()

    async def get_all_configs(self) -> List[StorageConfig]:
        return self.db.query(StorageConfig).filter(
            StorageConfig.is_active == True
        ).order_by(desc(StorageConfig.created_at)).all()

    async def set_default_config(self, config_id: UUID) -> bool:
        # ابتدا همه config ها را غیرپیش‌فرض کن
        await self.clear_default_configs()
        
        # config مورد نظر را پیش‌فرض کن
        config = self.db.query(StorageConfig).filter(StorageConfig.id == config_id).first()
        if not config:
            return False
        
        config.is_default = True
        self.db.commit()
        return True

    async def clear_default_configs(self):
        self.db.query(StorageConfig).update({"is_default": False})
        self.db.commit()

    async def delete_config(self, config_id: UUID) -> bool:
        config = self.db.query(StorageConfig).filter(StorageConfig.id == config_id).first()
        if not config:
            return False
        
        config.is_active = False
        self.db.commit()
        return True


class FileVerificationRepository(BaseRepository[FileVerification]):
    def __init__(self, db: Session):
        super().__init__(FileVerification, db)

    async def create_verification(
        self,
        file_id: UUID,
        module_name: str,
        verification_token: str,
        verification_data: Optional[Dict] = None
    ) -> FileVerification:
        verification = FileVerification(
            file_id=file_id,
            module_name=module_name,
            verification_token=verification_token,
            verification_data=verification_data
        )
        
        self.db.add(verification)
        self.db.commit()
        self.db.refresh(verification)
        return verification

    async def verify_file(
        self,
        file_id: UUID,
        verification_token: str,
        verified_by: UUID
    ) -> bool:
        verification = self.db.query(FileVerification).filter(
            and_(
                FileVerification.file_id == file_id,
                FileVerification.verification_token == verification_token,
                FileVerification.verified_at.is_(None)
            )
        ).first()
        
        if not verification:
            return False
        
        verification.verified_at = datetime.utcnow()
        verification.verified_by = verified_by
        
        self.db.commit()
        return True
