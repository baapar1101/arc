from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    Integer,
    String,
    Boolean,
    DateTime,
    Text,
    ForeignKey,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class BusinessPrintSettings(Base):
    """
    تنظیمات چاپ اسناد برای هر کسب‌وکار و به تفکیک نوع سند فاکتور.

    نکته:
    - رکوردی با document_type = 'all' به عنوان تنظیمات پیش‌فرض برای همه فاکتورها استفاده می‌شود.
    - در صورت وجود رکورد برای یک document_type مشخص، تنظیمات آن نوع، تنظیمات پیش‌فرض را override می‌کند.
    """

    __tablename__ = "business_print_settings"
    __table_args__ = (
        UniqueConstraint(
            "business_id",
            "document_type",
            name="uq_business_print_settings_business_doc_type",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)

    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # نوع سند: یکی از انواع فاکتور (invoice_sales, invoice_purchase, ...) یا 'all' برای تنظیمات عمومی
    document_type: Mapped[str] = mapped_column(String(50), nullable=False, index=True)

    # فلگ‌های کنترلی برای اجزای چاپ
    show_logo: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
    show_stamp: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
    show_payments: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
    show_installment_plan: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
    # QR لینک مشاهده آنلاین/اعتبارسنجی فاکتور در خروجی چاپ
    show_share_qr: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0")
    # پاورقی صفحهٔ PDF (زمان چاپ و نام تهیه‌کنندهٔ سند)
    show_footer_print_time: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
    show_footer_preparer: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")

    # متن ثابت انتهای فاکتور (پاورقی قابل تنظیم برای این نوع سند)
    footer_note: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )


