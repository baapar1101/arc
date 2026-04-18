from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import Integer, Numeric, DateTime, Text, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class WarehouseProductPlacement(Base):
	"""ثبت اینکه یک کالا در کدام محل انبار با چه مقداری قرار دارد (لایهٔ کمکی برای یافتن فیزیکی کالا)."""

	__tablename__ = "warehouse_product_placements"
	__table_args__ = (
		UniqueConstraint(
			"warehouse_id",
			"product_id",
			"warehouse_location_id",
			name="uq_wh_placements_wh_product_location",
		),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	warehouse_id: Mapped[int] = mapped_column(Integer, ForeignKey("warehouses.id", ondelete="CASCADE"), nullable=False, index=True)
	warehouse_location_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("warehouse_locations.id", ondelete="CASCADE"),
		nullable=False,
		index=True,
	)
	product_id: Mapped[int] = mapped_column(Integer, ForeignKey("products.id", ondelete="CASCADE"), nullable=False, index=True)

	quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))
	notes: Mapped[str | None] = mapped_column(Text, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	location = relationship("WarehouseLocation", back_populates="placements")
