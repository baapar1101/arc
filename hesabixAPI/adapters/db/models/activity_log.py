from __future__ import annotations

from datetime import datetime

from sqlalchemy import String, Integer, DateTime, ForeignKey, Text, JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class ActivityLog(Base):
	__tablename__ = "activity_logs"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	
	# شناسایی کاربر و کسب و کار
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
	business_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=True, index=True)
	
	# دسته‌بندی و نوع فعالیت
	category: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
	# مقادیر: "accounting", "warehouse", "product", "person", "business", "user", "settings", "invoice", "document", "other"
	
	action: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
	# مقادیر: "create", "update", "delete", "post", "cancel", "approve", "reject", "export", "import", "login", "logout", "password_change", etc.
	
	# شناسایی موجودیت مرتبط
	entity_type: Mapped[str | None] = mapped_column(String(50), nullable=True, index=True)
	# مقادیر: "invoice", "document", "warehouse_document", "product", "person", "account", "business", "user", "fiscal_year", etc.
	
	entity_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
	# شناسه موجودیت مرتبط (مثلاً invoice_id، product_id، person_id)
	
	# اطلاعات تغییرات
	description: Mapped[str] = mapped_column(Text, nullable=False)
	# توضیحات قابل خواندن برای انسان (مثلاً "فاکتور فروش INV-001 ایجاد شد")
	
	# داده‌های قبل و بعد (برای تغییرات)
	before_data: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	# داده‌های قبل از تغییر (فقط فیلدهای تغییر یافته)
	
	after_data: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	# داده‌های بعد از تغییر (فقط فیلدهای تغییر یافته)
	
	# اطلاعات اضافی
	extra_info: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	# اطلاعات اضافی مثل IP address، user agent، خطاها، و غیره
	
	# زمان‌ها
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False, index=True)
	
	# Relationships
	user = relationship("User", foreign_keys=[user_id])
	business = relationship("Business", foreign_keys=[business_id])

