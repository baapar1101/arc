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
	warehouse_location_id = Column(
		Integer,
		ForeignKey("warehouse_locations.id", ondelete="SET NULL"),
		nullable=True,
		index=True,
		comment="محل انبار (همگام با قرارگیری کالا پس از پست حواله)",
	)
	movement = Column(String(8), nullable=False)  # in|out
	quantity = Column(Numeric(18, 6), nullable=False)
	extra_info = Column(JSON, nullable=True)
	# برای کالاهای یونیک: لیست ID کالاهای یونیک
	instance_ids = Column(JSON, nullable=True, comment="لیست ID کالاهای یونیک (برای inventory_mode=unique)")

	document = relationship("WarehouseDocument", back_populates="lines")


