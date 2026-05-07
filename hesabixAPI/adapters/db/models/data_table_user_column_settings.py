from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, JSON, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class DataTableUserColumnSettings(Base):
	"""تنظیمات ستون‌های ویجت DataTable به‌ازای کاربر و کسب‌وکار (پایدار برای وب و چند worker)."""

	__tablename__ = "data_table_user_column_settings"
	__table_args__ = (
		UniqueConstraint("business_id", "user_id", "table_id", name="uq_dtucs_business_user_table"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
	table_id: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
	# همان ساختار JSON فرانت: visibleColumns, columnOrder, columnWidths, pinnedLeft, pinnedRight
	settings: Mapped[dict] = mapped_column(JSON, nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)
