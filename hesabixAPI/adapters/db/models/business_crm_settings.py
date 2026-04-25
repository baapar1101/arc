# noqa: D100
"""تنظیمات CRM سطح کسب‌وکار."""
from __future__ import annotations

from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class BusinessCrmSettings(Base):
	__tablename__ = "business_crm_settings"

	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), primary_key=True
	)
	allow_web_chat_file_upload: Mapped[bool] = mapped_column(
		Boolean, nullable=False, default=False, server_default="0"
	)
	updated_at: Mapped[datetime] = mapped_column(default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
