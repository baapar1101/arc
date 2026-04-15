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
    
    # تنظیمات محاسبه سود فاکتور
    invoice_profit_calculation_method: Mapped[str | None] = mapped_column(String(20), nullable=True, default="automatic", server_default="automatic", comment="روش محاسبه سود فاکتور: automatic, manual, disabled")
    invoice_profit_calculation_basis: Mapped[str | None] = mapped_column(String(30), nullable=True, default="purchase_price", server_default="purchase_price", comment="مبنای محاسبه سود: purchase_price, cost_price, average_cost, fifo, lifo, weighted_average, standard_cost, actual_cost")
    invoice_profit_include_overhead: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0", comment="آیا هزینه‌های سربار در محاسبه سود لحاظ شود؟")
    invoice_profit_overhead_type: Mapped[str | None] = mapped_column(String(30), nullable=True, default="none", server_default="none", comment="نوع هزینه‌های سربار: none, production_overhead, all_overhead, custom_percent")
    invoice_profit_overhead_percent: Mapped[float | None] = mapped_column(Numeric(5, 2), nullable=True, default=0, server_default="0", comment="درصد هزینه‌های سربار (در صورت انتخاب custom_percent)")
    invoice_profit_calculation_type: Mapped[str | None] = mapped_column(String(20), nullable=True, default="gross", server_default="gross", comment="نوع محاسبه سود: gross, net, both")
    
    # به‌روزرسانی قیمت پایه کالا از فاکتور قطعی (ارز کالا = ارز پیش‌فرض کسب‌وکار)
    invoice_sync_update_sales_price_enabled: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="0",
        comment="به‌روزرسانی قیمت فروش پایه از فاکتور فروش قطعی",
    )
    invoice_sync_update_purchase_price_enabled: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="0",
        comment="به‌روزرسانی قیمت خرید پایه از فاکتور خرید قطعی",
    )
    invoice_sync_sales_price_basis: Mapped[str | None] = mapped_column(
        String(40), nullable=True, default="net_after_line_discount", server_default="net_after_line_discount",
        comment="مبنای قیمت فروش: unit_price, net_after_line_discount, net_with_tax, cost_price",
    )
    invoice_sync_purchase_price_basis: Mapped[str | None] = mapped_column(
        String(40), nullable=True, default="net_after_line_discount", server_default="net_after_line_discount",
        comment="مبنای قیمت خرید: unit_price, net_after_line_discount, net_with_tax, cost_price",
    )
    # حواله انبار پس از ثبت فاکتور: none (بدون حواله)، draft (پیش‌نویس)، posted (قطعی فوری)
    invoice_warehouse_release_mode: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="draft",
        server_default="draft",
        comment="none | draft | posted",
    )

    # کنترل کسری هنگام قطعی کردن حواله (خروج): پیش‌فرض سخت‌گیرانه
    allow_negative_inventory_for_bulk: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default="0",
        comment="خروج با موجودی منفی برای کالاهای فله‌ای (inventory_mode غیر unique)",
    )
    allow_negative_inventory_for_unique: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default="0",
        comment="خروج با موجودی منفی برای کالاهای یونیک",
    )
    warehouse_transfer_require_positive_stock: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default="1",
        comment="انتقال بین انبار همیشه نیاز به موجودی کافی (نادیده گرفتن اجازه منفی)",
    )
    
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
    projects = relationship("Project", back_populates="business", cascade="all, delete-orphan")
    crm_process_definitions = relationship(
        "CrmProcessDefinition",
        back_populates="business",
        cascade="all, delete-orphan",
    )
    crm_leads = relationship("Lead", back_populates="business", cascade="all, delete-orphan")
    crm_deals = relationship("Deal", back_populates="business", cascade="all, delete-orphan")
    crm_activities = relationship("CrmActivity", back_populates="business", cascade="all, delete-orphan")