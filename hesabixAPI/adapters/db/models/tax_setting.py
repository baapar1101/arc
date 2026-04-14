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
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class TaxSetting(Base):
    __tablename__ = "tax_settings"
    __table_args__ = (
        UniqueConstraint("business_id", name="uq_tax_settings_business"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    created_by_user_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )

    tax_memory_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    economic_code: Mapped[str | None] = mapped_column(String(64), nullable=True)
    private_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    public_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    certificate: Mapped[str | None] = mapped_column(Text, nullable=True)
    certificate_request: Mapped[str | None] = mapped_column(Text, nullable=True)
    sandbox_mode: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0")

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )

    business = relationship("Business", lazy="joined")
    created_by = relationship("User", lazy="joined")


