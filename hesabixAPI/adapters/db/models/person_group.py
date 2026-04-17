from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import String, DateTime, Integer, ForeignKey, Text, UniqueConstraint, Boolean
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base

if TYPE_CHECKING:
    from adapters.db.models.business import Business
    from adapters.db.models.person import Person


class PersonGroup(Base):
    """گروه اشخاص: دسته‌بندی و قالب پیش‌فرض فیلدها. parent_id برای سلسله‌مراتب آینده."""

    __tablename__ = "person_groups"
    __table_args__ = (
        UniqueConstraint("business_id", "code", name="uq_person_groups_business_code"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
    parent_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("person_groups.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
        comment="والد برای سلسله‌مراتب؛ در فاز تک‌سطحی همیشه NULL",
    )

    name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    code: Mapped[int | None] = mapped_column(Integer, nullable=True, comment="کد اختیاری یکتا در هر کسب‌وکار")
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    profile_defaults: Mapped[str] = mapped_column(
        Text,
        nullable=False,
        default="{}",
        comment="JSON: مقادیر پیش‌فرض برای اشخاص جدید",
    )
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    business: Mapped["Business"] = relationship("Business", back_populates="person_groups")
    persons: Mapped[list["Person"]] = relationship("Person", back_populates="person_group")
