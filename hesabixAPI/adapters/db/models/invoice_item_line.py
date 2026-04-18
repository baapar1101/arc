from __future__ import annotations

from sqlalchemy import Column, Integer, Numeric, ForeignKey, JSON, Text, DateTime, String
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

	# شناسایی بهای تمام‌شده قطعی (دفتر) — در مقابل محاسبه تحلیلی زنده
	ledger_unit_cogs = Column(Numeric(18, 6), nullable=True, comment="بهای تمام‌شده واحد شناسایی‌شده")
	ledger_line_cogs = Column(Numeric(18, 2), nullable=True, comment="جمع بهای تمام‌شده خط شناسایی‌شده")
	ledger_line_gross_profit = Column(Numeric(18, 2), nullable=True, comment="سود ناخالص خط بر مبنای بهای قطعی")
	ledger_recognized_at = Column(DateTime, nullable=True, comment="زمان شناسایی قطعی")
	ledger_recognition_event = Column(String(40), nullable=True, comment="warehouse_document_posting | sales_invoice_document")


