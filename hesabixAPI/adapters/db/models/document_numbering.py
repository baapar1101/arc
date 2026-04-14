from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    Integer,
    String,
    Boolean,
    DateTime,
    ForeignKey,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class BusinessDocumentNumberingSetting(Base):
    __tablename__ = "business_document_numbering_settings"
    __table_args__ = (
        UniqueConstraint(
            "business_id",
            "document_type",
            name="uq_doc_numbering_business_type",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    document_type: Mapped[str] = mapped_column(String(50), nullable=False, index=True)

    prefix: Mapped[str | None] = mapped_column(String(20), nullable=True)
    include_date: Mapped[bool] = mapped_column(Boolean, default=True, server_default="1")
    calendar_type: Mapped[str] = mapped_column(
        String(10), default="gregorian", server_default="gregorian"
    )
    date_format: Mapped[str | None] = mapped_column(String(20), nullable=True)
    separator: Mapped[str] = mapped_column(String(5), default="-", server_default="-")
    start_number: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    number_padding: Mapped[int] = mapped_column(Integer, default=4, server_default="4")
    reset_period: Mapped[str | None] = mapped_column(String(20), nullable=True)

    custom_format: Mapped[str | None] = mapped_column(String(100), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="1")

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )

    business = relationship("Business", backref="document_numbering_settings")


class DocumentNumberCounter(Base):
    __tablename__ = "document_number_counters"
    __table_args__ = (
        UniqueConstraint(
            "business_id",
            "document_type",
            "date_bucket",
            name="uq_doc_number_counter_bucket",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    document_type: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
    date_bucket: Mapped[str] = mapped_column(String(32), nullable=False, default="GLOBAL")
    last_number: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )

    business = relationship("Business", backref="document_number_counters")
