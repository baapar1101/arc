from __future__ import annotations

from datetime import datetime

from sqlalchemy import String, Integer, Text, Boolean, ForeignKey, DateTime
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from adapters.db.session import Base


class BusinessFtpBackupSetting(Base):
	__tablename__ = "business_ftp_backup_settings"

	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), primary_key=True)
	host: Mapped[str] = mapped_column(String(255), nullable=False)
	port: Mapped[int] = mapped_column(Integer, nullable=False, default=21)
	username: Mapped[str] = mapped_column(String(255), nullable=False)
	password_encrypted: Mapped[str | None] = mapped_column(Text, nullable=True)
	remote_path: Mapped[str] = mapped_column(String(1024), nullable=False, default="/")
	passive: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	use_ftps: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
