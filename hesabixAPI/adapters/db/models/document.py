from __future__ import annotations

from datetime import date, datetime

from sqlalchemy import String, Integer, DateTime, Boolean, ForeignKey, JSON, Date, UniqueConstraint, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class Document(Base):
	__tablename__ = "documents"
	__table_args__ = (
		UniqueConstraint('business_id', 'code', name='uq_documents_business_code'),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	code: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	fiscal_year_id: Mapped[int] = mapped_column(Integer, ForeignKey("fiscal_years.id", ondelete="RESTRICT"), nullable=False, index=True)
	currency_id: Mapped[int] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False, index=True)
	created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False, index=True)
	registered_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	document_date: Mapped[date] = mapped_column(Date, nullable=False)
	document_type: Mapped[str] = mapped_column(String(50), nullable=False)
	is_proforma: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	description: Mapped[str | None] = mapped_column(Text, nullable=True)
	extra_info: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	developer_settings: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	project_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("projects.id", ondelete="SET NULL"), nullable=True, index=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	# Relationships
	business = relationship("Business", back_populates="documents")
	fiscal_year = relationship("FiscalYear", back_populates="documents")
	currency = relationship("Currency", back_populates="documents")
	created_by = relationship("User", foreign_keys=[created_by_user_id])
	project = relationship("Project")
	lines = relationship("DocumentLine", back_populates="document", cascade="all, delete-orphan")
	invoice_tag_links = relationship(
		"DocumentInvoiceTagLink", back_populates="document", cascade="all, delete-orphan"
	)


