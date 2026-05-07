from __future__ import annotations

from sqlalchemy import ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class ProductGeneralBarcodeAlias(Base):
    """
    ایندکس بارکدهای عمومی برای تطبیق دقیق اسکن و یکتایی در هر کسب‌وکار.
    مقدار token_normalized به صورت lowercase ذخیره می‌شود.
    """

    __tablename__ = "product_general_barcode_aliases"
    __table_args__ = (
        UniqueConstraint(
            "business_id",
            "token_normalized",
            name="uq_product_general_barcode_business_token",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    product_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("products.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    token_normalized: Mapped[str] = mapped_column(String(128), nullable=False)

    product = relationship("Product", foreign_keys=[product_id], lazy="select")
