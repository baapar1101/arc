from sqlalchemy import Column, String, Integer, DateTime, Boolean, Text, ForeignKey, JSON, BigInteger
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import uuid

from adapters.db.session import Base


class FileStorage(Base):
    __tablename__ = "file_storage"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    original_name = Column(String(255), nullable=False)
    stored_name = Column(String(255), nullable=False)
    file_path = Column(String(500), nullable=False)
    file_size = Column(Integer, nullable=False)
    mime_type = Column(String(100), nullable=False)
    storage_type = Column(String(20), nullable=False)  # local, ftp
    storage_config_id = Column(String(36), ForeignKey("storage_configs.id"), nullable=True)
    uploaded_by = Column(Integer, ForeignKey("users.id"), nullable=False)
    business_id = Column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=True, index=True)  # کسب‌وکار مالک فایل
    subscription_id = Column(Integer, ForeignKey("business_storage_subscriptions.id", ondelete="SET NULL"), nullable=True, index=True)  # پلن فعال در زمان آپلود
    module_context = Column(String(50), nullable=False)  # tickets, accounting, business_logo, etc.
    context_id = Column(String(36), nullable=True)  # ticket_id, document_id, etc.
    developer_data = Column(JSON, nullable=True)
    checksum = Column(String(64), nullable=True)
    is_active = Column(Boolean, default=True, nullable=False)
    is_temporary = Column(Boolean, default=False, nullable=False)
    is_verified = Column(Boolean, default=False, nullable=False)
    verification_token = Column(String(100), nullable=True)
    last_verified_at = Column(DateTime(timezone=True), nullable=True)
    expires_at = Column(DateTime(timezone=True), nullable=True)
    is_marked_for_deletion = Column(Boolean, default=False, nullable=False)  # برای حذف خودکار
    marked_for_deletion_at = Column(DateTime(timezone=True), nullable=True)  # زمان علامت‌گذاری برای حذف
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
    deleted_at = Column(DateTime(timezone=True), nullable=True)

    # Relationships
    uploader = relationship("User", foreign_keys=[uploaded_by])
    storage_config = relationship("StorageConfig", foreign_keys=[storage_config_id])
    business = relationship("Business", foreign_keys=[business_id])
    subscription = relationship("BusinessStorageSubscription", foreign_keys=[subscription_id])
    shares = relationship("FileStorageShare", back_populates="file", cascade="all, delete-orphan")


class FileStorageShare(Base):
	__tablename__ = "file_storage_shares"

	id = Column(Integer, primary_key=True, autoincrement=True)
	file_storage_id = Column(String(36), ForeignKey("file_storage.id", ondelete="CASCADE"), nullable=False, index=True)
	business_id = Column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	token_hash = Column(String(64), nullable=False, unique=True, index=True)
	password_hash = Column(String(255), nullable=True)
	expires_at = Column(DateTime(timezone=True), nullable=True)
	revoked_at = Column(DateTime(timezone=True), nullable=True)
	access_count = Column(Integer, nullable=False, default=0)
	last_access_at = Column(DateTime(timezone=True), nullable=True)
	created_by = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
	updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

	file = relationship("FileStorage", foreign_keys=[file_storage_id], back_populates="shares")
	business = relationship("Business", foreign_keys=[business_id])
	creator = relationship("User", foreign_keys=[created_by])


class StorageConfig(Base):
    __tablename__ = "storage_configs"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    name = Column(String(100), nullable=False)
    storage_type = Column(String(20), nullable=False)  # local, ftp
    is_default = Column(Boolean, default=False, nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    config_data = Column(JSON, nullable=False)
    created_by = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    # Relationships
    creator = relationship("User", foreign_keys=[created_by])


class FileVerification(Base):
    __tablename__ = "file_verifications"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    file_id = Column(String(36), ForeignKey("file_storage.id"), nullable=False)
    module_name = Column(String(50), nullable=False)
    verification_token = Column(String(100), nullable=False)
    verified_at = Column(DateTime(timezone=True), nullable=True)
    verified_by = Column(Integer, ForeignKey("users.id"), nullable=True)
    verification_data = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    # Relationships
    file = relationship("FileStorage", foreign_keys=[file_id])
    verifier = relationship("User", foreign_keys=[verified_by])
