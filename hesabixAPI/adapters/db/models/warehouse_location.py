from __future__ import annotations

from datetime import datetime

from sqlalchemy import Integer, String, DateTime, Text, ForeignKey, Boolean, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class WarehouseLocation(Base):
	"""سلسله‌مراتب مکان‌های فیزیکی داخل یک انبار (منطقه، ردیف، قفسه، سلول، ...)."""

	__tablename__ = "warehouse_locations"
	__table_args__ = (UniqueConstraint("warehouse_id", "code", name="uq_warehouse_locations_wh_code"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	warehouse_id: Mapped[int] = mapped_column(Integer, ForeignKey("warehouses.id", ondelete="CASCADE"), nullable=False, index=True)
	parent_id: Mapped[int | None] = mapped_column(
		Integer,
		ForeignKey("warehouse_locations.id", ondelete="RESTRICT"),
		nullable=True,
		index=True,
	)

	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name: Mapped[str] = mapped_column(String(255), nullable=False)
	location_kind: Mapped[str] = mapped_column(String(32), nullable=False, default="zone")
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	notes: Mapped[str | None] = mapped_column(Text, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	placements = relationship(
		"WarehouseProductPlacement",
		back_populates="location",
		cascade="all, delete-orphan",
		passive_deletes=True,
	)

