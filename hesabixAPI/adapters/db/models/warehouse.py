from __future__ import annotations

from datetime import datetime

from sqlalchemy import String, Integer, DateTime, Text, ForeignKey, UniqueConstraint, Boolean
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class Warehouse(Base):
    """
    انبارهای کسب‌وکار (حداقل‌های موردنیاز برای BOM و اسناد تولید)
    """

    __tablename__ = "warehouses"
    __table_args__ = (
        UniqueConstraint("business_id", "code", name="uq_warehouses_business_code"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)

    code: Mapped[str] = mapped_column(String(64), nullable=False, index=True, comment="کد یکتا در هر کسب‌وکار")
    name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    
    warehouse_keeper: Mapped[str | None] = mapped_column(String(255), nullable=True, comment="نام انباردار")
    phone: Mapped[str | None] = mapped_column(String(32), nullable=True, comment="تلفن")
    address: Mapped[str | None] = mapped_column(Text, nullable=True, comment="آدرس")
    postal_code: Mapped[str | None] = mapped_column(String(16), nullable=True, comment="کد پستی")

    is_default: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, index=True)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


