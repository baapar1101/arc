from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class PublicCatalogContactMessage(Base):
	"""پیام تماس ارسال‌شده از طریق API عمومی کاتالوگ."""

	__tablename__ = "public_catalog_contact_messages"

	id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	product_catalog_uuid: Mapped[str | None] = mapped_column(String(36), nullable=True)
	sender_name: Mapped[str] = mapped_column(String(200), nullable=False)
	sender_contact: Mapped[str] = mapped_column(String(200), nullable=False)
	message: Mapped[str] = mapped_column(Text, nullable=False)
	client_ip: Mapped[str | None] = mapped_column(String(64), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
