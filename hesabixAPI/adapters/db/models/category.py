from __future__ import annotations

from datetime import datetime

from sqlalchemy import String, Integer, DateTime, Boolean, ForeignKey, JSON, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class BusinessCategory(Base):
    """
    دسته‌بندی‌های کالا/خدمت برای هر کسب‌وکار با ساختار درختی
    - عناوین چندزبانه در فیلد JSON `title_translations` نگهداری می‌شود
    - نوع دسته‌بندی: product | service
    """
    __tablename__ = "categories"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
    parent_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("categories.id", ondelete="SET NULL"), nullable=True, index=True)
    # فیلد type حذف شده است (در مهاجرت بعدی)
    title_translations: Mapped[dict] = mapped_column(JSON, nullable=False, default={})
    description: Mapped[str | None] = mapped_column(Text, nullable=True, comment="توضیحات دسته‌بندی")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    # Relationships
    parent = relationship("BusinessCategory", remote_side=[id], backref="children")


