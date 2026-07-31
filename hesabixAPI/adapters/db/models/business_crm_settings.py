# noqa: D100
"""تنظیمات CRM سطح کسب‌وکار."""
from __future__ import annotations

from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, JSON
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
	allow_web_chat_voice: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0")
	# --- تنظیمات اتوماسیون فروش ---
	lead_sla_hours: Mapped[int] = mapped_column(Integer, nullable=False, default=24, server_default="24")
	auto_assign_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
	auto_assign_user_ids: Mapped[list | None] = mapped_column(JSON, nullable=True)
	auto_assign_cursor: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
	follow_up_notify_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
	stale_deal_days: Mapped[int] = mapped_column(Integer, nullable=False, default=14, server_default="14")
	score_rules: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	updated_at: Mapped[datetime] = mapped_column(default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
