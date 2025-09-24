from __future__ import annotations

from datetime import datetime
from enum import Enum

from sqlalchemy import String, DateTime, Integer, ForeignKey, Enum as SQLEnum, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class BusinessType(str, Enum):
    """نوع کسب و کار"""
    COMPANY = "شرکت"  # شرکت
    SHOP = "مغازه"  # مغازه
    STORE = "فروشگاه"  # فروشگاه
    UNION = "اتحادیه"  # اتحادیه
    CLUB = "باشگاه"  # باشگاه
    INSTITUTE = "موسسه"  # موسسه
    INDIVIDUAL = "شخصی"  # شخصی


class BusinessField(str, Enum):
    """زمینه فعالیت کسب و کار"""
    MANUFACTURING = "تولیدی"  # تولیدی
    TRADING = "بازرگانی"  # بازرگانی
    SERVICE = "خدماتی"  # خدماتی
    OTHER = "سایر"  # سایر


class Business(Base):
    __tablename__ = "businesses"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    business_type: Mapped[BusinessType] = mapped_column(SQLEnum(BusinessType), nullable=False)
    business_field: Mapped[BusinessField] = mapped_column(SQLEnum(BusinessField), nullable=False)
    owner_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    
    # فیلدهای جدید
    address: Mapped[str | None] = mapped_column(Text, nullable=True)
    phone: Mapped[str | None] = mapped_column(String(20), nullable=True)
    mobile: Mapped[str | None] = mapped_column(String(20), nullable=True)
    national_id: Mapped[str | None] = mapped_column(String(20), nullable=True, index=True)
    registration_number: Mapped[str | None] = mapped_column(String(50), nullable=True, index=True)
    economic_id: Mapped[str | None] = mapped_column(String(50), nullable=True, index=True)
    
    # فیلدهای جغرافیایی
    country: Mapped[str | None] = mapped_column(String(100), nullable=True)
    province: Mapped[str | None] = mapped_column(String(100), nullable=True)
    city: Mapped[str | None] = mapped_column(String(100), nullable=True)
    postal_code: Mapped[str | None] = mapped_column(String(20), nullable=True)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # Relationships - using business_permissions instead
    # users = relationship("BusinessUser", back_populates="business", cascade="all, delete-orphan")
