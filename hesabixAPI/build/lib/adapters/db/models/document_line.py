from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import Integer, DateTime, ForeignKey, JSON, Text, Numeric
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class DocumentLine(Base):
	__tablename__ = "document_lines"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	document_id: Mapped[int] = mapped_column(Integer, ForeignKey("documents.id", ondelete="CASCADE"), nullable=False, index=True)
	account_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("accounts.id", ondelete="RESTRICT"), nullable=True, index=True)
	debit: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	credit: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	description: Mapped[str | None] = mapped_column(Text, nullable=True)
	extra_info: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	developer_data: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	# Relationships
	document = relationship("Document", back_populates="lines")
	account = relationship("Account", back_populates="document_lines")


