from __future__ import annotations

from datetime import datetime

from sqlalchemy import String, Integer, DateTime, Boolean, ForeignKey, UniqueConstraint, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class DocumentInvoiceTag(Base):
	__tablename__ = "document_invoice_tags"
	__table_args__ = (
		UniqueConstraint("business_id", "name", name="uq_document_invoice_tags_business_name"),
		Index("ix_document_invoice_tags_business_id", "business_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	name: Mapped[str] = mapped_column(String(120), nullable=False)
	color: Mapped[str | None] = mapped_column(String(32), nullable=True)
	is_system: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)

	links: Mapped[list["DocumentInvoiceTagLink"]] = relationship(
		"DocumentInvoiceTagLink", back_populates="tag", cascade="all, delete-orphan"
	)


class DocumentInvoiceTagLink(Base):
	__tablename__ = "document_invoice_tag_links"
	__table_args__ = (Index("ix_document_invoice_tag_links_tag_id", "tag_id"),)

	document_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("documents.id", ondelete="CASCADE"), primary_key=True
	)
	tag_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("document_invoice_tags.id", ondelete="CASCADE"), primary_key=True
	)

	tag: Mapped["DocumentInvoiceTag"] = relationship("DocumentInvoiceTag", back_populates="links")
	document: Mapped["Document"] = relationship("Document", back_populates="invoice_tag_links")
