from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, JSON, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class BusinessUserQuickLink(Base):
	"""کاشی‌های دسترسی سریع داشبورد: به‌ازای هر کاربر در هر کسب‌وکار."""

	__tablename__ = "business_user_quick_links"
	__table_args__ = (UniqueConstraint("business_id", "user_id", name="uq_buql_business_user"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
	# items: [{ "id", "kind": "preset"|"external", "preset_id"?, "url"?, "title"?, "title_override"? }, ...]
	items: Mapped[list] = mapped_column(JSON, nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)
