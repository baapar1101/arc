from __future__ import annotations

from datetime import datetime
from typing import Any, Dict

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, JSON, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class BusinessCatalogSpecField(Base):
	"""قالب فیلدهای مشخصات کاتالوگ در سطح هر کسب‌وکار (شبکهٔ تأمین)."""

	__tablename__ = "business_catalog_spec_fields"
	__table_args__ = (
		UniqueConstraint("business_id", "title", name="uq_business_catalog_spec_fields_business_title"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("businesses.id", ondelete="CASCADE"),
		nullable=False,
		index=True,
	)
	title: Mapped[str] = mapped_column(String(255), nullable=False)
	description: Mapped[str | None] = mapped_column(Text, nullable=True)
	data_type: Mapped[str] = mapped_column(
		String(32),
		nullable=False,
		default="text",
		comment="text, number, date, select, boolean",
	)
	options: Mapped[Dict[str, Any] | None] = mapped_column(JSON, nullable=True)
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	is_required: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime,
		default=datetime.utcnow,
		onupdate=datetime.utcnow,
		nullable=False,
	)
