"""
مدل برای ذخیره فاکتورهای failed در Dead Letter Queue
"""

from __future__ import annotations

from sqlalchemy import Column, Integer, String, Text, DateTime, JSON, Index
from sqlalchemy.sql import func
from adapters.db.session import Base


class TaxFailedInvoice(Base):
    """جدول برای ذخیره فاکتورهای failed که نیاز به بررسی دستی دارند"""
    
    __tablename__ = "tax_failed_invoices"
    
    id = Column(Integer, primary_key=True, index=True)
    business_id = Column(Integer, nullable=False, index=True)
    invoice_id = Column(Integer, nullable=False, index=True)
    tracking_code = Column(String(100), nullable=True, index=True)
    
    error_code = Column(String(100), nullable=False)
    error_message = Column(Text, nullable=True)
    error_details = Column(JSON, nullable=True)
    
    attempt_count = Column(Integer, default=1, nullable=False)
    last_attempt_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    first_failed_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    
    # داده‌های فاکتور برای retry
    invoice_data = Column(JSON, nullable=True)
    
    # وضعیت
    status = Column(String(50), default="pending", nullable=False, index=True)  # pending, retrying, resolved, ignored
    
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
    
    __table_args__ = (
        Index("idx_tax_failed_business_status", "business_id", "status"),
        Index("idx_tax_failed_invoice", "business_id", "invoice_id"),
    )




