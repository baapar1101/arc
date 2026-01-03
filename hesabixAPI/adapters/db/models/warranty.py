from __future__ import annotations

from datetime import datetime
from typing import Optional
from sqlalchemy import (
    String,
    Integer,
    DateTime,
    ForeignKey,
    UniqueConstraint,
    Boolean,
    Text,
    Index,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy import JSON

from adapters.db.session import Base


class WarrantySetting(Base):
    """تنظیمات گارانتی برای هر کسب و کار"""
    __tablename__ = "warranty_settings"
    __table_args__ = (
        UniqueConstraint("business_id", name="uq_warranty_settings_business"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True, unique=True)
    
    # فرمت کد و سریال
    code_format: Mapped[str] = mapped_column(String(20), nullable=False, default="random", comment="فرمت کد: random, sequential, custom")
    code_prefix: Mapped[Optional[str]] = mapped_column(String(20), nullable=True, default="WR", comment="پیشوند کد")
    serial_format: Mapped[str] = mapped_column(String(20), nullable=False, default="random", comment="فرمت سریال: random, custom")
    serial_length: Mapped[Optional[int]] = mapped_column(Integer, nullable=True, default=12, comment="طول سریال برای رندوم")
    
    # تنظیمات امنیتی
    require_serial_verification: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, comment="نیاز به تأیید سریال کالا")
    require_product_instance_match: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, comment="نیاز به تطابق با product_instance")
    max_activation_attempts: Mapped[Optional[int]] = mapped_column(Integer, nullable=True, comment="حداکثر تلاش برای فعال‌سازی")
    activation_lockout_duration_minutes: Mapped[Optional[int]] = mapped_column(Integer, nullable=True, comment="مدت قفل شدن پس از تلاش‌های ناموفق")
    
    # تنظیمات مشتری
    require_customer_registration: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, comment="الزام ثبت مشتری در سیستم")
    auto_link_to_person: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, comment="اتصال خودکار به Person")
    
    # تنظیمات رهگیری
    enable_tracking_link: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, comment="فعال‌سازی لینک رهگیری")
    tracking_link_expires_days: Mapped[Optional[int]] = mapped_column(Integer, nullable=True, comment="مدت اعتبار لینک رهگیری")
    
    # تنظیمات اطلاع‌رسانی
    enable_sms_notification: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, comment="ارسال SMS هنگام فعال‌سازی")
    enable_email_notification: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, comment="ارسال ایمیل هنگام فعال‌سازی")
    
    # تنظیمات امنیتی اضافی
    security_features: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True, comment="تنظیمات امنیتی")
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # Relationships
    business: Mapped["Business"] = relationship("Business", foreign_keys=[business_id])


class WarrantyCode(Base):
    """کدهای گارانتی"""
    __tablename__ = "warranty_codes"
    __table_args__ = (
        UniqueConstraint("business_id", "code", name="uq_warranty_codes_business_code"),
        UniqueConstraint("business_id", "warranty_serial", name="uq_warranty_codes_business_serial"),
        Index("idx_warranty_codes_business_id", "business_id"),
        Index("idx_warranty_codes_code", "business_id", "code"),
        Index("idx_warranty_codes_warranty_serial", "business_id", "warranty_serial"),
        Index("idx_warranty_codes_product_id", "product_id"),
        Index("idx_warranty_codes_status", "status"),
        Index("idx_warranty_codes_tracking_link_code", "tracking_link_code"),
        Index("idx_warranty_codes_activated_by_person_id", "activated_by_person_id"),
        Index("idx_warranty_codes_business_person", "business_id", "activated_by_person_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
    
    # کد و سریال گارانتی
    code: Mapped[str] = mapped_column(String(50), nullable=False, comment="کد گارانتی یکتا")
    warranty_serial: Mapped[str] = mapped_column(String(50), nullable=False, comment="سریال گارانتی یکتا")
    
    # اطلاعات کالا
    product_id: Mapped[int] = mapped_column(Integer, ForeignKey("products.id", ondelete="CASCADE"), nullable=False, index=True)
    product_instance_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("product_instances.id", ondelete="SET NULL"), nullable=True, comment="شناسه instance کالا")
    
    # وضعیت
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="generated", comment="وضعیت: generated, activated, expired, used, revoked")
    
    # اطلاعات تولید
    generated_by_user_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    generated_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow)
    
    # اطلاعات فعال‌سازی
    activated_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    activated_by_person_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("persons.id", ondelete="SET NULL"), nullable=True, comment="شناسه Person مشتری")
    activated_by_customer_info: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True, comment="اطلاعات مشتری غیرثبت‌شده")
    
    # اطلاعات انقضا
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    warranty_duration_days: Mapped[int] = mapped_column(Integer, nullable=False, comment="مدت گارانتی به روز")
    
    # لینک رهگیری
    tracking_link_code: Mapped[Optional[str]] = mapped_column(String(50), nullable=True, comment="کد یکتا برای لینک رهگیری")
    
    # اطلاعات اضافی
    extra_metadata: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True, comment="اطلاعات اضافی")
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # Relationships
    business: Mapped["Business"] = relationship("Business", foreign_keys=[business_id])
    product: Mapped["Product"] = relationship("Product", foreign_keys=[product_id])
    product_instance: Mapped[Optional["ProductInstance"]] = relationship("ProductInstance", foreign_keys=[product_instance_id])
    generated_by_user: Mapped[Optional["User"]] = relationship("User", foreign_keys=[generated_by_user_id])
    activated_by_person: Mapped[Optional["Person"]] = relationship("Person", foreign_keys=[activated_by_person_id])
    activations: Mapped[list["WarrantyActivation"]] = relationship("WarrantyActivation", back_populates="warranty_code", cascade="all, delete-orphan")
    tracking_events: Mapped[list["WarrantyTracking"]] = relationship("WarrantyTracking", back_populates="warranty_code", cascade="all, delete-orphan")
    tracking_links: Mapped[list["WarrantyTrackingLink"]] = relationship("WarrantyTrackingLink", back_populates="warranty_code", cascade="all, delete-orphan")


class WarrantyActivation(Base):
    """فعال‌سازی‌های گارانتی"""
    __tablename__ = "warranty_activations"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    warranty_code_id: Mapped[int] = mapped_column(Integer, ForeignKey("warranty_codes.id", ondelete="CASCADE"), nullable=False, index=True)
    
    # اطلاعات مشتری
    person_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("persons.id", ondelete="SET NULL"), nullable=True, index=True)
    product_instance_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("product_instances.id", ondelete="SET NULL"), nullable=True)
    
    # اطلاعات وارد شده
    warranty_serial: Mapped[str] = mapped_column(String(50), nullable=False, comment="سریال گارانتی وارد شده")
    product_serial: Mapped[Optional[str]] = mapped_column(String(128), nullable=True, comment="سریال کالا وارد شده")
    
    # اطلاعات تماس
    customer_name: Mapped[str] = mapped_column(String(255), nullable=False)
    customer_phone: Mapped[str] = mapped_column(String(20), nullable=False)
    customer_email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    
    # اطلاعات فعال‌سازی
    activation_date: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow)
    ip_address: Mapped[Optional[str]] = mapped_column(String(45), nullable=True)
    user_agent: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    verification_method: Mapped[Optional[str]] = mapped_column(String(50), nullable=True, comment="روش تأیید: serial_match, product_instance_match, manual")
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    
    # Relationships
    warranty_code: Mapped["WarrantyCode"] = relationship("WarrantyCode", back_populates="activations")
    person: Mapped[Optional["Person"]] = relationship("Person", foreign_keys=[person_id])
    product_instance: Mapped[Optional["ProductInstance"]] = relationship("ProductInstance", foreign_keys=[product_instance_id])


class WarrantyTracking(Base):
    """تاریخچه رهگیری گارانتی"""
    __tablename__ = "warranty_tracking"
    __table_args__ = (
        Index("idx_warranty_tracking_warranty_code_id", "warranty_code_id"),
        Index("idx_warranty_tracking_person_id", "person_id"),
        Index("idx_warranty_tracking_event_type", "event_type"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    warranty_code_id: Mapped[int] = mapped_column(Integer, ForeignKey("warranty_codes.id", ondelete="CASCADE"), nullable=False, index=True)
    
    # اطلاعات مرتبط
    product_instance_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("product_instances.id", ondelete="SET NULL"), nullable=True)
    person_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("persons.id", ondelete="SET NULL"), nullable=True, index=True)
    
    # اطلاعات رویداد
    event_type: Mapped[str] = mapped_column(String(50), nullable=False, comment="نوع رویداد: activation, repair_request, repair_completed, replacement, expired, revoked")
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    performed_by_user_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    
    # Relationships
    warranty_code: Mapped["WarrantyCode"] = relationship("WarrantyCode", back_populates="tracking_events")
    product_instance: Mapped[Optional["ProductInstance"]] = relationship("ProductInstance", foreign_keys=[product_instance_id])
    person: Mapped[Optional["Person"]] = relationship("Person", foreign_keys=[person_id])
    performed_by_user: Mapped[Optional["User"]] = relationship("User", foreign_keys=[performed_by_user_id])


class WarrantyTrackingLink(Base):
    """لینک‌های رهگیری یکتا برای Person"""
    __tablename__ = "warranty_tracking_links"
    __table_args__ = (
        UniqueConstraint("link_code", name="uq_warranty_tracking_links_link_code"),
        Index("idx_warranty_tracking_links_link_code", "link_code"),
        Index("idx_warranty_tracking_links_person_id", "person_id"),
        Index("idx_warranty_tracking_links_warranty_code_id", "warranty_code_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    warranty_code_id: Mapped[int] = mapped_column(Integer, ForeignKey("warranty_codes.id", ondelete="CASCADE"), nullable=False, index=True)
    person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="CASCADE"), nullable=False, index=True)
    
    # اطلاعات لینک
    link_code: Mapped[str] = mapped_column(String(50), nullable=False, comment="کد یکتا لینک")
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True, comment="تاریخ انقضا")
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    
    # آمار دسترسی
    access_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    last_accessed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # Relationships
    warranty_code: Mapped["WarrantyCode"] = relationship("WarrantyCode", back_populates="tracking_links")
    person: Mapped["Person"] = relationship("Person", foreign_keys=[person_id])

