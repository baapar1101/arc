"""
مدل‌های دیتابیس برای افزونه مدیریت تعمیرگاه
"""
from __future__ import annotations

from datetime import datetime
from typing import Optional
from decimal import Decimal

from sqlalchemy import (
    String,
    Integer,
    DateTime,
    ForeignKey,
    UniqueConstraint,
    Boolean,
    Text,
    Numeric,
    Index,
    Date,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.mysql import JSON

from adapters.db.session import Base


class RepairShopSettings(Base):
    """تنظیمات تعمیرگاه برای هر کسب‌وکار"""
    __tablename__ = "repair_shop_settings"
    __table_args__ = (
        UniqueConstraint("business_id", name="uq_repair_shop_settings_business"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, 
        ForeignKey("businesses.id", ondelete="CASCADE"), 
        nullable=False,
        index=True,
        unique=True
    )
    
    # تنظیمات شماره‌گذاری
    receipt_code_format: Mapped[str] = mapped_column(
        String(20), 
        nullable=False, 
        default="sequential",
        comment="فرمت کد: random, sequential, custom"
    )
    receipt_code_prefix: Mapped[str] = mapped_column(
        String(10), 
        nullable=False, 
        default="REC",
        comment="پیشوند کد رسید"
    )
    
    # تنظیمات نوتیفیکیشن
    auto_send_sms_on_receive: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    auto_send_sms_on_status_change: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    auto_send_email_on_receive: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    auto_send_email_on_status_change: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    
    # قالب‌های پیام
    sms_templates: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True, comment="قالب‌های پیامک")
    email_templates: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True, comment="قالب‌های ایمیل")
    
    # تنظیمات پیش‌فرض
    default_service_product_id: Mapped[Optional[int]] = mapped_column(
        Integer, 
        ForeignKey("products.id", ondelete="SET NULL"),
        nullable=True,
        comment="محصول پیش‌فرض خدمات تعمیر"
    )
    default_warehouse_id: Mapped[Optional[int]] = mapped_column(
        Integer,
        ForeignKey("warehouses.id", ondelete="SET NULL"),
        nullable=True,
        comment="انبار پیش‌فرض قطعات"
    )
    
    # متادیتا
    extra_settings: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True, comment="تنظیمات اضافی")
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # Relationships
    business: Mapped["Business"] = relationship("Business", foreign_keys=[business_id])


class RepairTechnician(Base):
    """تعمیرکاران"""
    __tablename__ = "repair_technicians"
    __table_args__ = (
        UniqueConstraint("business_id", "code", name="uq_repair_technicians_business_code"),
        Index("idx_repair_technicians_business_id", "business_id"),
        Index("idx_repair_technicians_person_id", "person_id"),
        Index("idx_repair_technicians_is_active", "is_active"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, 
        ForeignKey("businesses.id", ondelete="CASCADE"), 
        nullable=False,
        index=True
    )
    person_id: Mapped[int] = mapped_column(
        Integer, 
        ForeignKey("persons.id", ondelete="RESTRICT"), 
        nullable=False,
        index=True,
        comment="شناسه Person (از جدول اشخاص)"
    )
    code: Mapped[str] = mapped_column(
        String(50), 
        nullable=False,
        comment="کد تعمیرکار"
    )
    
    # تنظیمات حق‌الزحمه
    commission_type: Mapped[str] = mapped_column(
        String(20), 
        nullable=False, 
        default="percentage",
        comment="نوع حق‌الزحمه: fixed, percentage, case_by_case"
    )
    commission_value: Mapped[Decimal] = mapped_column(
        Numeric(18, 2), 
        nullable=False, 
        default=0,
        comment="مبلغ فیکس یا درصد"
    )
    
    # وضعیت
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    
    # متادیتا
    extra_info: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True, comment="اطلاعات اضافی")
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # Relationships
    business: Mapped["Business"] = relationship("Business", foreign_keys=[business_id])
    person: Mapped["Person"] = relationship("Person", foreign_keys=[person_id])


class RepairOrder(Base):
    """سفارش تعمیر (رسید دریافت کالا)"""
    __tablename__ = "repair_orders"
    __table_args__ = (
        UniqueConstraint("business_id", "code", name="uq_repair_orders_business_code"),
        Index("idx_repair_orders_business_id", "business_id"),
        Index("idx_repair_orders_status", "status"),
        Index("idx_repair_orders_customer", "customer_person_id"),
        Index("idx_repair_orders_technician", "assigned_technician_id"),
        Index("idx_repair_orders_warranty", "warranty_code_id"),
        Index("idx_repair_orders_received_at", "received_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, 
        ForeignKey("businesses.id", ondelete="CASCADE"), 
        nullable=False,
        index=True
    )
    code: Mapped[str] = mapped_column(
        String(50), 
        nullable=False,
        comment="کد یکتا رسید (مثلاً REC-2025-0001)"
    )
    
    # اطلاعات مشتری
    customer_person_id: Mapped[int] = mapped_column(
        Integer, 
        ForeignKey("persons.id", ondelete="RESTRICT"), 
        nullable=False,
        index=True,
        comment="مشتری از جدول persons (phone و email از persons دریافت می‌شود)"
    )
    
    # اطلاعات کالا
    product_id: Mapped[Optional[int]] = mapped_column(
        Integer, 
        ForeignKey("products.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
        comment="کالا از جدول products (اگر در سیستم باشد)"
    )
    product_name: Mapped[str] = mapped_column(
        String(255), 
        nullable=False,
        comment="نام کالا (برای متفرقه)"
    )
    product_serial: Mapped[Optional[str]] = mapped_column(
        String(100), 
        nullable=True,
        comment="سریال کالا"
    )
    warranty_code_id: Mapped[Optional[int]] = mapped_column(
        Integer,
        ForeignKey("warranty_codes.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
        comment="کد گارانتی (اگر تحت گارانتی باشد)"
    )
    
    # وضعیت و توضیحات
    status: Mapped[str] = mapped_column(
        String(50), 
        nullable=False, 
        default="received",
        comment="وضعیت: received, assigned, in_progress, waiting_parts, testing, completed_fixed, completed_unfixable, ready_for_pickup, delivered, cancelled"
    )
    problem_description: Mapped[str] = mapped_column(
        Text, 
        nullable=False,
        comment="شرح مشکل"
    )
    customer_notes: Mapped[Optional[str]] = mapped_column(
        Text, 
        nullable=True,
        comment="یادداشت مشتری"
    )
    technician_notes: Mapped[Optional[str]] = mapped_column(
        Text, 
        nullable=True,
        comment="یادداشت تعمیرکار"
    )
    
    # تعمیرکار
    assigned_technician_id: Mapped[Optional[int]] = mapped_column(
        Integer,
        ForeignKey("repair_technicians.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
        comment="تعمیرکار اختصاص داده شده"
    )
    
    # هزینه‌ها
    estimated_cost: Mapped[Optional[Decimal]] = mapped_column(
        Numeric(18, 2), 
        nullable=True,
        comment="هزینه برآوردی"
    )
    final_cost: Mapped[Decimal] = mapped_column(
        Numeric(18, 2), 
        nullable=False, 
        default=0,
        comment="هزینه نهایی"
    )
    parts_cost: Mapped[Decimal] = mapped_column(
        Numeric(18, 2), 
        nullable=False, 
        default=0,
        comment="هزینه قطعات"
    )
    labor_cost: Mapped[Decimal] = mapped_column(
        Numeric(18, 2), 
        nullable=False, 
        default=0,
        comment="دستمزد تعمیر"
    )
    technician_commission: Mapped[Decimal] = mapped_column(
        Numeric(18, 2), 
        nullable=False, 
        default=0,
        comment="حق‌الزحمه تعمیرکار"
    )
    
    # تاریخ‌ها
    received_at: Mapped[datetime] = mapped_column(
        DateTime, 
        nullable=False, 
        default=datetime.utcnow,
        comment="تاریخ دریافت"
    )
    estimated_delivery_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime, 
        nullable=True,
        comment="تاریخ تحویل تقریبی"
    )
    completed_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime, 
        nullable=True,
        comment="تاریخ اتمام تعمیر"
    )
    delivered_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime, 
        nullable=True,
        comment="تاریخ تحویل کالا"
    )
    
    # اطلاعات اداری
    fiscal_year_id: Mapped[int] = mapped_column(
        Integer, 
        ForeignKey("fiscal_years.id", ondelete="RESTRICT"), 
        nullable=False,
        index=True
    )
    currency_id: Mapped[int] = mapped_column(
        Integer, 
        ForeignKey("currencies.id", ondelete="RESTRICT"), 
        nullable=False,
        index=True
    )
    created_by_user_id: Mapped[int] = mapped_column(
        Integer, 
        ForeignKey("users.id", ondelete="RESTRICT"), 
        nullable=False,
        index=True
    )
    
    # متادیتا
    extra_info: Mapped[Optional[dict]] = mapped_column(
        JSON, 
        nullable=True,
        comment="اطلاعات اضافی: warehouse_document_id, attachments, etc."
    )
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # Relationships
    business: Mapped["Business"] = relationship("Business", foreign_keys=[business_id])
    customer: Mapped["Person"] = relationship("Person", foreign_keys=[customer_person_id])
    product: Mapped[Optional["Product"]] = relationship("Product", foreign_keys=[product_id])
    warranty_code: Mapped[Optional["WarrantyCode"]] = relationship("WarrantyCode", foreign_keys=[warranty_code_id])
    technician: Mapped[Optional["RepairTechnician"]] = relationship("RepairTechnician", foreign_keys=[assigned_technician_id])
    fiscal_year: Mapped["FiscalYear"] = relationship("FiscalYear", foreign_keys=[fiscal_year_id])
    currency: Mapped["Currency"] = relationship("Currency", foreign_keys=[currency_id])
    created_by: Mapped["User"] = relationship("User", foreign_keys=[created_by_user_id])


class RepairOrderPart(Base):
    """قطعات استفاده شده در تعمیر"""
    __tablename__ = "repair_order_parts"
    __table_args__ = (
        Index("idx_repair_order_parts_repair_order_id", "repair_order_id"),
        Index("idx_repair_order_parts_product_id", "product_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    repair_order_id: Mapped[int] = mapped_column(
        Integer, 
        ForeignKey("repair_orders.id", ondelete="CASCADE"), 
        nullable=False,
        index=True
    )
    product_id: Mapped[int] = mapped_column(
        Integer, 
        ForeignKey("products.id", ondelete="RESTRICT"), 
        nullable=False,
        index=True,
        comment="قطعه از جدول products"
    )
    quantity: Mapped[Decimal] = mapped_column(
        Numeric(18, 6), 
        nullable=False,
        comment="تعداد"
    )
    unit_price: Mapped[Decimal] = mapped_column(
        Numeric(18, 2), 
        nullable=False,
        comment="قیمت واحد"
    )
    total_price: Mapped[Decimal] = mapped_column(
        Numeric(18, 2), 
        nullable=False,
        comment="قیمت کل"
    )
    warehouse_id: Mapped[Optional[int]] = mapped_column(
        Integer,
        ForeignKey("warehouses.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
        comment="انبار خروج قطعه"
    )
    description: Mapped[Optional[str]] = mapped_column(
        String(500), 
        nullable=True,
        comment="توضیحات"
    )
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    
    # Relationships
    repair_order: Mapped["RepairOrder"] = relationship("RepairOrder", foreign_keys=[repair_order_id])
    product: Mapped["Product"] = relationship("Product", foreign_keys=[product_id])
    warehouse: Mapped[Optional["Warehouse"]] = relationship("Warehouse", foreign_keys=[warehouse_id])


class RepairOrderStatus(Base):
    """تاریخچه وضعیت‌ها (کارتابل)"""
    __tablename__ = "repair_order_statuses"
    __table_args__ = (
        Index("idx_repair_order_statuses_repair_order_id", "repair_order_id"),
        Index("idx_repair_order_statuses_created_at", "created_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    repair_order_id: Mapped[int] = mapped_column(
        Integer, 
        ForeignKey("repair_orders.id", ondelete="CASCADE"), 
        nullable=False,
        index=True
    )
    status: Mapped[str] = mapped_column(
        String(50), 
        nullable=False,
        comment="وضعیت جدید"
    )
    notes: Mapped[Optional[str]] = mapped_column(
        Text, 
        nullable=True,
        comment="یادداشت تغییر وضعیت"
    )
    
    # اطلاعات اقدام‌کننده
    created_by_user_id: Mapped[int] = mapped_column(
        Integer, 
        ForeignKey("users.id", ondelete="RESTRICT"), 
        nullable=False,
        index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime, 
        nullable=False, 
        default=datetime.utcnow
    )
    
    # اطلاعات نوتیفیکیشن
    sms_sent: Mapped[bool] = mapped_column(
        Boolean, 
        nullable=False, 
        default=False,
        comment="آیا پیامک ارسال شده"
    )
    sms_sent_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime, 
        nullable=True,
        comment="زمان ارسال پیامک"
    )
    email_sent: Mapped[bool] = mapped_column(
        Boolean, 
        nullable=False, 
        default=False,
        comment="آیا ایمیل ارسال شده"
    )
    email_sent_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime, 
        nullable=True,
        comment="زمان ارسال ایمیل"
    )
    
    # Relationships
    repair_order: Mapped["RepairOrder"] = relationship("RepairOrder", foreign_keys=[repair_order_id])
    created_by: Mapped["User"] = relationship("User", foreign_keys=[created_by_user_id])


class RepairOrderAttachment(Base):
    """ضمائم و تصاویر تعمیر"""
    __tablename__ = "repair_order_attachments"
    __table_args__ = (
        Index("idx_repair_order_attachments_repair_order_id", "repair_order_id"),
        Index("idx_repair_order_attachments_type", "attachment_type"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    repair_order_id: Mapped[int] = mapped_column(
        Integer, 
        ForeignKey("repair_orders.id", ondelete="CASCADE"), 
        nullable=False,
        index=True
    )
    file_storage_id: Mapped[str] = mapped_column(
        String(36), 
        nullable=False,
        index=True,
        comment="شناسه فایل در file_storage (no FK due to type incompatibility)"
    )
    file_type: Mapped[str] = mapped_column(
        String(50), 
        nullable=False,
        comment="نوع فایل: image, video, document"
    )
    attachment_type: Mapped[str] = mapped_column(
        String(50), 
        nullable=False,
        comment="نوع ضمیمه: before_repair, during_repair, after_repair"
    )
    description: Mapped[Optional[str]] = mapped_column(
        String(500), 
        nullable=True,
        comment="توضیحات"
    )
    uploaded_by_user_id: Mapped[int] = mapped_column(
        Integer, 
        ForeignKey("users.id", ondelete="RESTRICT"), 
        nullable=False,
        index=True
    )
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    
    # Relationships
    repair_order: Mapped["RepairOrder"] = relationship("RepairOrder", foreign_keys=[repair_order_id])
    uploaded_by: Mapped["User"] = relationship("User", foreign_keys=[uploaded_by_user_id])


class RepairInvoice(Base):
    """ارتباط بین سفارش تعمیر و فاکتور فروش"""
    __tablename__ = "repair_invoices"
    __table_args__ = (
        Index("idx_repair_invoices_repair_order_id", "repair_order_id"),
        Index("idx_repair_invoices_document_id", "document_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    repair_order_id: Mapped[int] = mapped_column(
        Integer, 
        ForeignKey("repair_orders.id", ondelete="CASCADE"), 
        nullable=False,
        index=True,
        comment="سفارش تعمیر"
    )
    document_id: Mapped[int] = mapped_column(
        Integer, 
        ForeignKey("documents.id", ondelete="RESTRICT"), 
        nullable=False,
        index=True,
        comment="فاکتور فروش"
    )
    invoice_type: Mapped[str] = mapped_column(
        String(50), 
        nullable=False,
        comment="نوع فاکتور: repair_service, parts_only, both"
    )
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    
    # Relationships
    repair_order: Mapped["RepairOrder"] = relationship("RepairOrder", foreign_keys=[repair_order_id])
    document: Mapped["Document"] = relationship("Document", foreign_keys=[document_id])

