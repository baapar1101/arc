from __future__ import annotations

from datetime import datetime

from sqlalchemy import Integer, ForeignKey, Text, DateTime, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class BusinessFrequentDescription(Base):
	"""عبارات پرتکرار برای پر کردن دستی فیلدهای شرح؛ بدون FK به اسناد."""

	__tablename__ = "business_frequent_descriptions"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	scope: Mapped[str] = mapped_column(String(64), nullable=False, default="general", server_default="general")
	text: Mapped[str] = mapped_column(Text, nullable=False)
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	business = relationship("Business", back_populates="frequent_descriptions")
