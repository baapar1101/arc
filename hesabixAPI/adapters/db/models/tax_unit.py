from datetime import datetime
from sqlalchemy import String, Integer, Boolean, DateTime, Text, Numeric
from sqlalchemy.orm import Mapped, mapped_column
from adapters.db.session import Base


class TaxUnit(Base):
    """
    موجودیت واحد مالیاتی
    - مدیریت واحدهای مالیاتی مختلف برای کسب‌وکارها
    - پشتیبانی از انواع مختلف مالیات (فروش، خرید، ارزش افزوده و...)
    """
    
    __tablename__ = "tax_units"
    
    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(Integer, nullable=False, index=True, comment="شناسه کسب‌وکار")
    name: Mapped[str] = mapped_column(String(255), nullable=False, comment="نام واحد مالیاتی")
    code: Mapped[str] = mapped_column(String(64), nullable=False, comment="کد واحد مالیاتی")
    description: Mapped[str | None] = mapped_column(Text, nullable=True, comment="توضیحات")
    tax_rate: Mapped[float | None] = mapped_column(Numeric(5, 2), nullable=True, comment="نرخ مالیات (درصد)")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, comment="وضعیت فعال/غیرفعال")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
