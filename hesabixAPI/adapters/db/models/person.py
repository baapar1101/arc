from __future__ import annotations

from datetime import datetime
from enum import Enum

from sqlalchemy import String, DateTime, Integer, ForeignKey, Enum as SQLEnum, Text, Boolean
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class PersonType(str, Enum):
    """نوع شخص"""
    CUSTOMER = "مشتری"  # مشتری
    MARKETER = "بازاریاب"  # بازاریاب
    EMPLOYEE = "کارمند"  # کارمند
    SUPPLIER = "تامین‌کننده"  # تامین‌کننده
    PARTNER = "همکار"  # همکار
    SELLER = "فروشنده"  # فروشنده


class Person(Base):
    __tablename__ = "persons"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
    
    # اطلاعات پایه
    alias_name: Mapped[str] = mapped_column(String(255), nullable=False, index=True, comment="نام مستعار (الزامی)")
    first_name: Mapped[str | None] = mapped_column(String(100), nullable=True, comment="نام")
    last_name: Mapped[str | None] = mapped_column(String(100), nullable=True, comment="نام خانوادگی")
    person_type: Mapped[PersonType] = mapped_column(SQLEnum(PersonType), nullable=False, comment="نوع شخص")
    company_name: Mapped[str | None] = mapped_column(String(255), nullable=True, comment="نام شرکت")
    payment_id: Mapped[str | None] = mapped_column(String(100), nullable=True, comment="شناسه پرداخت")
    
    # اطلاعات اقتصادی
    national_id: Mapped[str | None] = mapped_column(String(20), nullable=True, index=True, comment="شناسه ملی")
    registration_number: Mapped[str | None] = mapped_column(String(50), nullable=True, comment="شماره ثبت")
    economic_id: Mapped[str | None] = mapped_column(String(50), nullable=True, comment="شناسه اقتصادی")
    
    # اطلاعات تماس
    country: Mapped[str | None] = mapped_column(String(100), nullable=True, comment="کشور")
    province: Mapped[str | None] = mapped_column(String(100), nullable=True, comment="استان")
    city: Mapped[str | None] = mapped_column(String(100), nullable=True, comment="شهرستان")
    address: Mapped[str | None] = mapped_column(Text, nullable=True, comment="آدرس")
    postal_code: Mapped[str | None] = mapped_column(String(20), nullable=True, comment="کد پستی")
    phone: Mapped[str | None] = mapped_column(String(20), nullable=True, comment="تلفن")
    mobile: Mapped[str | None] = mapped_column(String(20), nullable=True, comment="موبایل")
    fax: Mapped[str | None] = mapped_column(String(20), nullable=True, comment="فکس")
    email: Mapped[str | None] = mapped_column(String(255), nullable=True, comment="پست الکترونیکی")
    website: Mapped[str | None] = mapped_column(String(255), nullable=True, comment="وب‌سایت")
    
    # وضعیت
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, comment="وضعیت فعال بودن")
    
    # زمان‌بندی
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # Relationships
    business: Mapped["Business"] = relationship("Business", back_populates="persons")
    bank_accounts: Mapped[list["PersonBankAccount"]] = relationship("PersonBankAccount", back_populates="person", cascade="all, delete-orphan")


class PersonBankAccount(Base):
    __tablename__ = "person_bank_accounts"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="CASCADE"), nullable=False, index=True)
    
    # اطلاعات حساب بانکی
    bank_name: Mapped[str] = mapped_column(String(255), nullable=False, comment="نام بانک")
    account_number: Mapped[str | None] = mapped_column(String(50), nullable=True, comment="شماره حساب")
    card_number: Mapped[str | None] = mapped_column(String(20), nullable=True, comment="شماره کارت")
    sheba_number: Mapped[str | None] = mapped_column(String(30), nullable=True, comment="شماره شبا")
    
    # وضعیت
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, comment="وضعیت فعال بودن")
    
    # زمان‌بندی
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # Relationships
    person: Mapped["Person"] = relationship("Person", back_populates="bank_accounts")
