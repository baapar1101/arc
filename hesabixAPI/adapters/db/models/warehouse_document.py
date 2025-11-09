from __future__ import annotations

from sqlalchemy import Column, Integer, String, Date, DateTime, ForeignKey, JSON, Enum
from sqlalchemy.orm import relationship
from datetime import datetime

from adapters.db.session import Base


class WarehouseDocument(Base):
	__tablename__ = "warehouse_documents"

	id = Column(Integer, primary_key=True, autoincrement=True)
	business_id = Column(Integer, nullable=False, index=True)
	fiscal_year_id = Column(Integer, nullable=True, index=True)
	code = Column(String(64), nullable=False, unique=True, index=True)
	document_date = Column(Date, nullable=False, index=True)
	status = Column(String(16), nullable=False, default="draft")  # draft|posted|cancelled
	doc_type = Column(String(32), nullable=False)  # receipt|issue|transfer|production_in|production_out|adjustment
	warehouse_id_from = Column(Integer, nullable=True, index=True)
	warehouse_id_to = Column(Integer, nullable=True, index=True)
	source_type = Column(String(32), nullable=True)  # invoice|manual|api
	source_document_id = Column(Integer, nullable=True, index=True)
	extra_info = Column(JSON, nullable=True)
	created_by_user_id = Column(Integer, nullable=True)
	created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
	updated_at = Column(DateTime, nullable=False, default=datetime.utcnow)

	lines = relationship("WarehouseDocumentLine", back_populates="document", cascade="all, delete-orphan")

	def touch(self):
		self.updated_at = datetime.utcnow()


