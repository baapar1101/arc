from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy import Integer, ForeignKey, String, Text, DateTime, Boolean, JSON
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class ReportTemplate(Base):
	__tablename__ = "report_templates"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True, nullable=False)
	# ماژول هدف این قالب (مثلاً: invoices, persons, kardex, receipts, products, ...)
	module_key: Mapped[str] = mapped_column(String(64), index=True, nullable=False)
	# زیرنوع اختیاری (مثلاً: list, detail، یا نوع فاکتور: sales, purchase, ...)
	subtype: Mapped[Optional[str]] = mapped_column(String(64), index=True, nullable=True)
	name: Mapped[str] = mapped_column(String(160), nullable=False)
	description: Mapped[Optional[str]] = mapped_column(String(512), nullable=True)

	engine: Mapped[str] = mapped_column(String(32), default="jinja2", nullable=False)
	status: Mapped[str] = mapped_column(String(16), default="draft", index=True)  # draft | published
	is_default: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
	version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)

	# محتوای قالب
	content_html: Mapped[str] = mapped_column(Text, nullable=False)
	content_css: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	header_html: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	footer_html: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

	# تنظیمات صفحه
	paper_size: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)  # A4, Letter, ...
	orientation: Mapped[Optional[str]] = mapped_column(String(16), nullable=True)  # portrait, landscape
	margins: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)  # {top, right, bottom, left} mm

	assets: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)  # مسیرها/داده‌های باینری base64

	created_by: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


