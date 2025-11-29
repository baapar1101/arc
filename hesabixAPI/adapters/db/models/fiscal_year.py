from __future__ import annotations

from datetime import date, datetime

from sqlalchemy import String, Date, DateTime, Integer, Boolean, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class FiscalYear(Base):
	__tablename__ = "fiscal_years"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	title: Mapped[str] = mapped_column(String(255), nullable=False)
	start_date: Mapped[date] = mapped_column(Date, nullable=False)
	end_date: Mapped[date] = mapped_column(Date, nullable=False)
	is_last: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	inventory_valuation_method: Mapped[str | None] = mapped_column(String(20), nullable=True, default="FIFO", comment="روش ارزیابی انبار: FIFO, LIFO, WeightedAverage")
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	# Relationships
	business = relationship("Business", back_populates="fiscal_years")
	documents = relationship("Document", back_populates="fiscal_year", cascade="all, delete-orphan")


