from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, Index, Integer, JSON, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class QuickSaleInvoiceJob(Base):
	"""Durable outbox row for a quick-sale invoice request."""

	__tablename__ = "quick_sale_invoice_jobs"

	id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
	request_id: Mapped[str] = mapped_column(String(160), nullable=False)
	payload: Mapped[dict] = mapped_column(JSON, nullable=False)
	user_can_select_fx_rate: Mapped[bool] = mapped_column(default=False, nullable=False)
	user_can_change_invoice_unit_price: Mapped[bool] = mapped_column(default=True, nullable=False)
	status: Mapped[str] = mapped_column(String(16), default="queued", nullable=False)
	attempt_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
	available_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	locked_until: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	invoice_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True)
	invoice_code: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
	error_code: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
	error_message: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	error_details: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
	finished_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)

	__table_args__ = (
		UniqueConstraint("business_id", "request_id", name="uq_quick_sale_invoice_jobs_request"),
		Index("ix_quick_sale_invoice_jobs_due", "status", "available_at", "locked_until"),
		Index("ix_quick_sale_invoice_jobs_user_created", "business_id", "user_id", "created_at"),
	)
