from __future__ import annotations

from datetime import datetime
from sqlalchemy import Integer, Boolean, ForeignKey, DateTime, String, UniqueConstraint, JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class QuickSalesSetting(Base):
    """
    تنظیمات فروش سریع برای هر کسب‌وکار
    """
    __tablename__ = "quick_sales_settings"
    __table_args__ = (
        UniqueConstraint("business_id", name="uq_quick_sales_settings_business"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, 
        ForeignKey("businesses.id", ondelete="CASCADE"), 
        nullable=False, 
        index=True
    )

    # مشتری ناشناس
    default_anonymous_customer_id: Mapped[int | None] = mapped_column(
        Integer, 
        ForeignKey("persons.id", ondelete="SET NULL"), 
        nullable=True,
        comment="شناسه مشتری پیش‌فرض برای فروش ناشناس"
    )
    auto_create_anonymous_customer: Mapped[bool] = mapped_column(
        Boolean, 
        nullable=False, 
        default=True, 
        server_default="1",
        comment="ایجاد خودکار مشتری ناشناس در صورت عدم وجود"
    )
    anonymous_customer_name: Mapped[str | None] = mapped_column(
        String(255), 
        nullable=True,
        comment="نام مشتری ناشناس"
    )

    # انبار و صندوق
    default_warehouse_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("warehouses.id", ondelete="SET NULL"),
        nullable=True,
        comment="انبار پیش‌فرض برای فروش سریع"
    )
    default_cash_register_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("cash_registers.id", ondelete="SET NULL"),
        nullable=True,
        comment="صندوق پیش‌فرض برای پرداخت نقدی"
    )
    default_currency_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("currencies.id", ondelete="SET NULL"),
        nullable=True,
        comment="ارز پیش‌فرض برای فاکتورهای فروش سریع"
    )
    default_price_list_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("price_lists.id", ondelete="SET NULL"),
        nullable=True,
        comment="لیست قیمت پیش‌فرض برای فروش سریع"
    )

    # تنظیمات چاپ
    auto_print: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default="0",
        comment="چاپ خودکار پس از ثبت"
    )
    print_template_id: Mapped[int | None] = mapped_column(
        Integer,
        nullable=True,
        comment="قالب چاپ پیش‌فرض"
    )

    # تنظیمات موجودی
    enable_warehouse_document: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default="1",
        comment="فعال/غیرفعال کردن صدور حواله انبار"
    )
    warehouse_document_type: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="posted",
        server_default="posted",
        comment="نوع سند حواله انبار: draft یا posted"
    )
    auto_post_warehouse: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default="1",
        comment="(قدیمی - برای سازگاری) قطعی خودکار حواله انبار"
    )
    show_inventory: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default="1",
        comment="نمایش موجودی در صفحه فروش سریع"
    )

    # تنظیمات حسابداری
    auto_create_payment_document: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default="1",
        comment="ثبت خودکار سند پرداخت جداگانه"
    )

    # پیش‌فرض اشتراک‌گذاری فاکتور (وقتی سند دریافت ثبت نمی‌شود)
    default_share_online_payment: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default="1",
        comment="پرداخت آنلاین در لینک اشتراک فاکتور",
    )
    default_share_gateway_id: Mapped[int | None] = mapped_column(
        Integer,
        nullable=True,
        comment="درگاه پیش‌فرض برای لینک پرداخت فاکتور",
    )
    default_share_channels: Mapped[list | None] = mapped_column(
        JSON,
        nullable=True,
        comment='کانال‌های پیش‌فرض ارسال: sms, email, native',
    )
    default_share_expiry_hours: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=168,
        server_default="168",
        comment="مدت اعتبار لینک اشتراک (ساعت)",
    )

    # تنظیمات نمایش
    show_purchase_price: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default="0",
        comment="نمایش قیمت خرید"
    )

    # Audit
    created_at: Mapped[datetime] = mapped_column(
        DateTime, 
        default=datetime.utcnow, 
        nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, 
        default=datetime.utcnow, 
        onupdate=datetime.utcnow, 
        nullable=False
    )

    # Relationships
    business = relationship("Business", backref="quick_sales_setting", uselist=False)
    anonymous_customer = relationship("Person", foreign_keys=[default_anonymous_customer_id])
    default_warehouse = relationship("Warehouse", foreign_keys=[default_warehouse_id])
    default_cash_register = relationship("CashRegister", foreign_keys=[default_cash_register_id])
    default_currency = relationship("Currency", foreign_keys=[default_currency_id])
    default_price_list = relationship("PriceList", foreign_keys=[default_price_list_id])

