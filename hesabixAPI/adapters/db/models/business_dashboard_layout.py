from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, JSON, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class BusinessUserDashboardLayout(Base):
	"""چیدمان داشبورد کسب‌وکار به‌ازای کاربر و breakpoint (وب/چند worker)."""

	__tablename__ = "business_user_dashboard_layouts"
	__table_args__ = (
		UniqueConstraint("business_id", "user_id", "breakpoint", name="uq_budl_business_user_bp"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
	breakpoint: Mapped[str] = mapped_column(String(8), nullable=False, index=True)
	# items: [{ key, order, colSpan, rowSpan, hidden }, ...]
	items: Mapped[list] = mapped_column(JSON, nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class BusinessDashboardDefaultLayout(Base):
	"""چیدمان پیش‌فرض منتشرشده توسط مالک کسب‌وکار."""

	__tablename__ = "business_dashboard_default_layouts"
	__table_args__ = (UniqueConstraint("business_id", "breakpoint", name="uq_bddl_business_bp"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	breakpoint: Mapped[str] = mapped_column(String(8), nullable=False, index=True)
	items: Mapped[list] = mapped_column(JSON, nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)
