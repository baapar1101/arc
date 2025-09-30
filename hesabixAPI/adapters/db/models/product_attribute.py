from __future__ import annotations

from datetime import datetime

from sqlalchemy import String, Integer, DateTime, Text, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class ProductAttribute(Base):
    """
    ویژگی‌های کالا/خدمت در سطح هر کسب‌وکار
    - عنوان و توضیحات ساده (بدون چندزبانه)
    - هر عنوان در هر کسب‌وکار یکتا باشد
    """
    __tablename__ = "product_attributes"
    __table_args__ = (
        UniqueConstraint('business_id', 'title', name='uq_product_attributes_business_title'),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)

    title: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


