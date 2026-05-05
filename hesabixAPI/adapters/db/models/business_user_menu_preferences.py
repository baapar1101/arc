from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, JSON, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class BusinessUserMenuPreference(Base):
	"""شخصی‌سازی منوی پنل: به‌ازای هر کاربر در هر کسب‌وکار."""

	__tablename__ = "business_user_menu_preferences"
	__table_args__ = (UniqueConstraint("business_id", "user_id", name="uq_bump_business_user"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
	# schema:
	# {
	#   "root_order": ["dashboard", ...],
	#   "hidden_keys": ["reports", ...],
	#   "children_order": {"banking": ["bank_accounts", ...]}
	# }
	preferences: Mapped[dict] = mapped_column(JSON, nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)
