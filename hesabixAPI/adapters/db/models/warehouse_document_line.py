from __future__ import annotations

from sqlalchemy import Column, Integer, Numeric, ForeignKey, JSON, String
from sqlalchemy.orm import relationship

from adapters.db.session import Base


class WarehouseDocumentLine(Base):
	__tablename__ = "warehouse_document_lines"

	id = Column(Integer, primary_key=True, autoincrement=True)
	warehouse_document_id = Column(Integer, ForeignKey("warehouse_documents.id", ondelete="CASCADE"), nullable=False, index=True)
	product_id = Column(Integer, nullable=False, index=True)
	warehouse_id = Column(Integer, nullable=True, index=True)
	movement = Column(String(8), nullable=False)  # in|out
	quantity = Column(Numeric(18, 6), nullable=False)
	cost_price = Column(Numeric(18, 6), nullable=True)
	cogs_amount = Column(Numeric(18, 6), nullable=True)
	extra_info = Column(JSON, nullable=True)

	document = relationship("WarehouseDocument", back_populates="lines")


