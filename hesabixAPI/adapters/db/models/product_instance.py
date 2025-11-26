from __future__ import annotations

from datetime import datetime, date
from sqlalchemy import (
    Column,
    Integer,
    String,
    ForeignKey,
    DateTime,
    Date,
    JSON,
    UniqueConstraint,
    Index,
)
from sqlalchemy.orm import relationship

from adapters.db.session import Base


class ProductInstance(Base):
    """
    موجودیت کالای یونیک - هر واحد از کالا به صورت جداگانه ردیابی می‌شود
    - سریال نامبر یکتا
    - بارکد یکتا (اختیاری)
    - ویژگی‌های کالا در custom_attributes
    - وضعیت: available, sold, warranty, defective
    """

    __tablename__ = "product_instances"
    __table_args__ = (
        UniqueConstraint("business_id", "serial_number", name="uq_product_instances_business_serial"),
        UniqueConstraint("business_id", "barcode", name="uq_product_instances_business_barcode"),
        Index("idx_product_instances_product", "product_id"),
        Index("idx_product_instances_warehouse", "warehouse_id"),
        Index("idx_product_instances_status", "status"),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    business_id = Column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
    product_id = Column(Integer, ForeignKey("products.id", ondelete="CASCADE"), nullable=False, index=True)
    
    # اطلاعات یکتا
    serial_number = Column(String(128), nullable=False, comment="شماره سریال یکتا")
    barcode = Column(String(128), nullable=True, comment="بارکد یکتا (اختیاری)")
    
    # موقعیت فعلی
    warehouse_id = Column(Integer, ForeignKey("warehouses.id", ondelete="SET NULL"), nullable=True, index=True)
    status = Column(String(16), nullable=False, default="available", comment="وضعیت: available, sold, warranty, defective")
    
    # ویژگی‌های کالا (JSON)
    custom_attributes = Column(JSON, nullable=True, comment="ویژگی‌های کالا مانند رنگ، سایز، مدل و ...")
    
    # تاریخ‌ها
    entry_date = Column(Date, nullable=False, default=date.today, comment="تاریخ ورود به انبار")
    last_movement_date = Column(Date, nullable=True, comment="تاریخ آخرین جابجایی")
    
    # اطلاعات فروش
    current_invoice_id = Column(Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True, index=True, comment="فاکتور فروش (اگر فروخته شده)")
    
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationships
    product = relationship("Product", foreign_keys=[product_id], lazy="select")
    warehouse = relationship("Warehouse", foreign_keys=[warehouse_id], lazy="select")
    invoice = relationship("Document", foreign_keys=[current_invoice_id], lazy="select")

