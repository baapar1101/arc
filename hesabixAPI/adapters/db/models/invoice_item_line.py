from __future__ import annotations

from sqlalchemy import Column, Integer, Numeric, ForeignKey, JSON, Text
from sqlalchemy.orm import relationship

from adapters.db.session import Base


class InvoiceItemLine(Base):
	__tablename__ = "invoice_item_lines"

	id = Column(Integer, primary_key=True, autoincrement=True)
	document_id = Column(Integer, ForeignKey("documents.id", ondelete="CASCADE"), nullable=False, index=True)
	product_id = Column(Integer, nullable=False, index=True)
	quantity = Column(Numeric(18, 6), nullable=False)
	description = Column(Text, nullable=True)
	extra_info = Column(JSON, nullable=True)


