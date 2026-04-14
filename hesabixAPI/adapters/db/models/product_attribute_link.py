from __future__ import annotations

from datetime import datetime

from sqlalchemy import Integer, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class ProductAttributeLink(Base):
    """لینک بین محصول و ویژگی‌ها (چندبه‌چند)"""
    __tablename__ = "product_attribute_links"
    __table_args__ = (
        UniqueConstraint("product_id", "attribute_id", name="uq_product_attribute_links_unique"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    product_id: Mapped[int] = mapped_column(Integer, ForeignKey("products.id", ondelete="CASCADE"), nullable=False, index=True)
    attribute_id: Mapped[int] = mapped_column(Integer, ForeignKey("product_attributes.id", ondelete="CASCADE"), nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


