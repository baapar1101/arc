from __future__ import annotations

from datetime import datetime
from enum import Enum

from sqlalchemy import String, DateTime, Integer, ForeignKey, Enum as SQLEnum, Text, Numeric, Boolean
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
    default_currency_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=True, index=True)
    
    # فیلدهای جدید
    address: Mapped[str | None] = mapped_column(Text, nullable=True)
    phone: Mapped[str | None] = mapped_column(String(20), nullable=True)
    mobile: Mapped[str | None] = mapped_column(String(20), nullable=True)
    national_id: Mapped[str | None] = mapped_column(String(20), nullable=True, index=True)
    registration_number: Mapped[str | None] = mapped_column(String(50), nullable=True, index=True)
    economic_id: Mapped[str | None] = mapped_column(String(50), nullable=True, index=True)

    # شناسه فایل‌های ذخیره‌سازی شده برای لوگو و مهر (ارجاع به جدول file_storage)
    logo_file_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    stamp_file_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    
    # فیلدهای جغرافیایی
    country: Mapped[str | None] = mapped_column(String(100), nullable=True)
    province: Mapped[str | None] = mapped_column(String(100), nullable=True)
    city: Mapped[str | None] = mapped_column(String(100), nullable=True)
    postal_code: Mapped[str | None] = mapped_column(String(20), nullable=True)
    
    # تنظیمات اعتبار مشتریان
    default_credit_limit: Mapped[float | None] = mapped_column(Numeric(14, 2), nullable=True, comment="سقف اعتبار پیشفرض اشخاص")
    check_credit_enabled_by_default: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0", comment="بررسی اعتبار مشتریان به صورت پیشفرض")
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # Soft Delete fields
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, index=True)
    deletion_requested_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    deletion_requested_by: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id"), nullable=True)
    deletion_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    auto_delete_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, index=True)  # 30 days after deleted_at
    
    # Relationships
    persons: Mapped[list["Person"]] = relationship("Person", back_populates="business", cascade="all, delete-orphan")
    fiscal_years = relationship("FiscalYear", back_populates="business", cascade="all, delete-orphan")
    currencies = relationship("Currency", secondary="business_currencies", back_populates="businesses")
    default_currency = relationship("Currency", foreign_keys="[Business.default_currency_id]", uselist=False)
    documents = relationship("Document", back_populates="business", cascade="all, delete-orphan")
    accounts = relationship("Account", back_populates="business", cascade="all, delete-orphan")
