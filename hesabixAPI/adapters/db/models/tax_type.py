from datetime import datetime
from sqlalchemy import String, Integer, DateTime, Text
from sqlalchemy.orm import Mapped, mapped_column
from adapters.db.session import Base


class TaxType(Base):
    """
    موجودیت نوع مالیات
    - نگهداری انواع مالیات استاندارد سازمان امور مالیاتی
    - عمومی برای همه کسب‌وکارها (بدون وابستگی به کسب‌وکار خاص)
    - مثال: ارزش افزوده گروه «دارو»، «دخانیات» و ...
    """

    __tablename__ = "tax_types"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False, comment="عنوان نوع مالیات")
    code: Mapped[str] = mapped_column(String(64), nullable=False, unique=True, index=True, comment="کد یکتا برای نوع مالیات")
    description: Mapped[str | None] = mapped_column(Text, nullable=True, comment="توضیحات")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


