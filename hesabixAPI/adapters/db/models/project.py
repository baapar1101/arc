from __future__ import annotations

from datetime import datetime, date

from sqlalchemy import String, Integer, DateTime, Boolean, ForeignKey, JSON, Date, Text, UniqueConstraint, Numeric
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class Project(Base):
	"""
	مدل پروژه - برای دسته‌بندی و ردیابی اسناد مالی بر اساس پروژه
	"""
	__tablename__ = "projects"
	__table_args__ = (
		UniqueConstraint('business_id', 'code', name='uq_projects_business_code'),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	
	# اطلاعات پایه
	code: Mapped[str] = mapped_column(String(50), nullable=False, index=True, comment="کد یکتا پروژه")
	name: Mapped[str] = mapped_column(String(255), nullable=False, index=True, comment="نام پروژه")
	description: Mapped[str | None] = mapped_column(Text, nullable=True, comment="توضیحات پروژه")
	
	# وضعیت پروژه
	status: Mapped[str] = mapped_column(String(20), nullable=False, default="active", comment="وضعیت: active, completed, on_hold, cancelled")
	
	# تاریخ‌ها
	start_date: Mapped[date | None] = mapped_column(Date, nullable=True, comment="تاریخ شروع")
	end_date: Mapped[date | None] = mapped_column(Date, nullable=True, comment="تاریخ پایان")
	
	# اطلاعات مالی (اختیاری)
	budget: Mapped[float | None] = mapped_column(Numeric(18, 2), nullable=True, comment="بودجه پروژه")
	currency_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="SET NULL"), nullable=True, index=True)
	
	# مدیر پروژه (اختیاری)
	manager_user_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True, comment="مدیر پروژه")
	
	# مشتری/تامین‌کننده مرتبط (اختیاری)
	person_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("persons.id", ondelete="SET NULL"), nullable=True, index=True, comment="شخص مرتبط با پروژه")
	
	# اطلاعات اضافی
	extra_info: Mapped[dict | None] = mapped_column(JSON, nullable=True, comment="اطلاعات اضافی: tags, custom_fields, etc.")
	
	# وضعیت فعال/غیرفعال
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, comment="فعال/غیرفعال")
	
	# زمان‌بندی
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
	created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False, index=True)
	
	# Relationships
	business = relationship("Business", back_populates="projects")
	currency = relationship("Currency")
	manager = relationship("User", foreign_keys=[manager_user_id])
	created_by = relationship("User", foreign_keys=[created_by_user_id])
	person = relationship("Person")

