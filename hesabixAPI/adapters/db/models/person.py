from __future__ import annotations

from datetime import datetime
from enum import Enum

from sqlalchemy import String, DateTime, Integer, ForeignKey, Enum as SQLEnum, Text, UniqueConstraint, Numeric, Boolean
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
    SHAREHOLDER = "سهامدار"  # سهامدار


class Person(Base):
    __tablename__ = "persons"
    __table_args__ = (
        UniqueConstraint('business_id', 'code', name='uq_persons_business_code'),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
    person_group_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("person_groups.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
        comment="گروه اشخاص (دسته‌بندی و قالب پیش‌فرض)",
    )

    # اطلاعات پایه
    code: Mapped[int | None] = mapped_column(Integer, nullable=True, comment="کد یکتا در هر کسب و کار")
    alias_name: Mapped[str] = mapped_column(String(255), nullable=False, index=True, comment="نام مستعار (الزامی)")
    first_name: Mapped[str | None] = mapped_column(String(100), nullable=True, comment="نام")
    last_name: Mapped[str | None] = mapped_column(String(100), nullable=True, comment="نام خانوادگی")
    person_types: Mapped[str] = mapped_column(Text, nullable=False, comment="لیست انواع شخص به صورت JSON")
    company_name: Mapped[str | None] = mapped_column(String(255), nullable=True, comment="نام شرکت")
    name_prefix: Mapped[str | None] = mapped_column(String(64), nullable=True, comment="پیشوند نام (آقای، خانم، شرکت، …)")
    legal_entity_type: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default="natural",
        server_default="natural",
        comment="نوع حقوقی: natural=حقیقی، legal=حقوقی",
    )
    payment_id: Mapped[str | None] = mapped_column(String(100), nullable=True, comment="شناسه پرداخت")
    # سهام
    share_count: Mapped[int | None] = mapped_column(Integer, nullable=True, comment="تعداد سهام (فقط برای سهامدار)")

    # تنظیمات پورسانت برای بازاریاب/فروشنده
    commission_sale_percent: Mapped[float | None] = mapped_column(Numeric(5, 2), nullable=True, comment="درصد پورسانت از فروش")
    commission_sales_return_percent: Mapped[float | None] = mapped_column(Numeric(5, 2), nullable=True, comment="درصد پورسانت از برگشت از فروش")
    commission_sales_amount: Mapped[float | None] = mapped_column(Numeric(12, 2), nullable=True, comment="مبلغ فروش مبنا برای پورسانت")
    commission_sales_return_amount: Mapped[float | None] = mapped_column(Numeric(12, 2), nullable=True, comment="مبلغ برگشت از فروش مبنا برای پورسانت")
    commission_exclude_discounts: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0", comment="عدم محاسبه تخفیف در پورسانت")
    commission_exclude_additions_deductions: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0", comment="عدم محاسبه اضافات و کسورات فاکتور در پورسانت")
    commission_post_in_invoice_document: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0", comment="ثبت پورسانت در سند حسابداری فاکتور")
    
    # اعتبار
    credit_limit: Mapped[float | None] = mapped_column(Numeric(14, 2), nullable=True, comment="سقف اعتبار شخص")
    credit_check_enabled: Mapped[bool | None] = mapped_column(Boolean, nullable=True, comment="فعال بودن بررسی اعتبار برای شخص (خالی: تبعیت از تنظیمات کسب‌وکار)")
    
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
    
    # زمان‌بندی
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # Relationships
    business: Mapped["Business"] = relationship("Business", back_populates="persons")
    person_group: Mapped["PersonGroup | None"] = relationship("PersonGroup", back_populates="persons")
    bank_accounts: Mapped[list["PersonBankAccount"]] = relationship("PersonBankAccount", back_populates="person", cascade="all, delete-orphan")
    crm_deals: Mapped[list["Deal"]] = relationship("Deal", back_populates="person", foreign_keys="[Deal.person_id]")
    crm_activities: Mapped[list["CrmActivity"]] = relationship("CrmActivity", back_populates="person", cascade="all, delete-orphan")


class PersonBankAccount(Base):
    __tablename__ = "person_bank_accounts"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="CASCADE"), nullable=False, index=True)
    
    # اطلاعات حساب بانکی
    bank_name: Mapped[str] = mapped_column(String(255), nullable=False, comment="نام بانک")
    account_number: Mapped[str | None] = mapped_column(String(50), nullable=True, comment="شماره حساب")
    card_number: Mapped[str | None] = mapped_column(String(20), nullable=True, comment="شماره کارت")
    sheba_number: Mapped[str | None] = mapped_column(String(30), nullable=True, comment="شماره شبا")
    
    # زمان‌بندی
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # Relationships
    person: Mapped["Person"] = relationship("Person", back_populates="bank_accounts")
