from __future__ import annotations

from datetime import datetime
from sqlalchemy import String, Integer, DateTime
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class ProductTaxCode(Base):
    """
    جدول کدهای مالیاتی کالا که از فایل‌های XML سازمان امور مالیاتی وارد می‌شود.
    """

    __tablename__ = "product_tax_codes"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    code: Mapped[str] = mapped_column(String(32), nullable=False, unique=True, index=True)
    description: Mapped[str] = mapped_column(String(1024), nullable=False)
    vat_rate: Mapped[str | None] = mapped_column(String(16), nullable=True)
    taxable_status: Mapped[str | None] = mapped_column(String(64), nullable=True)
    run_date: Mapped[str | None] = mapped_column(String(32), nullable=True)
    expiration_date: Mapped[str | None] = mapped_column(String(32), nullable=True)
    create_date: Mapped[str | None] = mapped_column(String(32), nullable=True)
    last_edit_date: Mapped[str | None] = mapped_column(String(32), nullable=True)
    source_type: Mapped[str | None] = mapped_column(String(128), nullable=True)
    pricing_description: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    source_filename: Mapped[str | None] = mapped_column(String(255), nullable=True)
    source_checksum: Mapped[str | None] = mapped_column(String(64), nullable=True)
    imported_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )

