from __future__ import annotations

from datetime import datetime
from enum import Enum

from sqlalchemy import (
    String,
    Integer,
    DateTime,
    ForeignKey,
    UniqueConstraint,
    Numeric,
    Enum as SQLEnum,
    Index,
    JSON,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class CheckType(str, Enum):
    RECEIVED = "RECEIVED"
    TRANSFERRED = "TRANSFERRED"


class CheckStatus(str, Enum):
    RECEIVED_ON_HAND = "RECEIVED_ON_HAND"          # چک دریافتی در دست
    TRANSFERRED_ISSUED = "TRANSFERRED_ISSUED"      # چک پرداختنی صادر و تحویل شده
    DEPOSITED = "DEPOSITED"                        # سپرده به بانک (در جریان وصول)
    CLEARED = "CLEARED"                            # پاس/وصول شده
    ENDORSED = "ENDORSED"                          # واگذار شده به شخص ثالث
    RETURNED = "RETURNED"                          # عودت شده
    BOUNCED = "BOUNCED"                            # برگشت خورده
    CANCELLED = "CANCELLED"                        # ابطال شده

class HolderType(str, Enum):
    BUSINESS = "BUSINESS"
    BANK = "BANK"
    PERSON = "PERSON"

class Check(Base):
    __tablename__ = "checks"
    __table_args__ = (
        # پیشنهاد: یکتا بودن شماره چک در سطح کسب‌وکار
        UniqueConstraint('business_id', 'check_number', name='uq_checks_business_check_number'),
        # پیشنهاد: یکتا بودن شناسه صیاد در سطح کسب‌وکار (چند NULL مجاز است)
        UniqueConstraint('business_id', 'sayad_code', name='uq_checks_business_sayad_code'),
        Index('ix_checks_business_type', 'business_id', 'type'),
        Index('ix_checks_business_person', 'business_id', 'person_id'),
        Index('ix_checks_business_issue_date', 'business_id', 'issue_date'),
        Index('ix_checks_business_due_date', 'business_id', 'due_date'),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)

    type: Mapped[CheckType] = mapped_column(SQLEnum(CheckType, name="check_type"), nullable=False, index=True)
    person_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("persons.id", ondelete="SET NULL"), nullable=True, index=True)

    issue_date: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)
    due_date: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)

    check_number: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
    sayad_code: Mapped[str | None] = mapped_column(String(16), nullable=True, index=True)

    bank_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    branch_name: Mapped[str | None] = mapped_column(String(255), nullable=True)

    amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False)
    currency_id: Mapped[int] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False, index=True)

    # وضعیت و نگهدارنده
    status: Mapped[CheckStatus | None] = mapped_column(SQLEnum(CheckStatus, name="check_status"), nullable=True, index=True)
    status_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    current_holder_type: Mapped[HolderType | None] = mapped_column(SQLEnum(HolderType, name="check_holder_type"), nullable=True, index=True)
    current_holder_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
    last_action_document_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True, index=True)
    developer_data: Mapped[dict | None] = mapped_column(JSON, nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    # روابط
    business = relationship("Business", backref="checks")
    person = relationship("Person", lazy="joined")
    currency = relationship("Currency")
    last_action_document = relationship("Document")
    reconciliation_items = relationship("CheckReconciliationItem", back_populates="check", cascade="all, delete-orphan")


class CheckReconciliation(Base):
    __tablename__ = "check_reconciliations"
    __table_args__ = (
        Index('ix_check_reconciliations_business', 'business_id'),
        Index('ix_check_reconciliations_created_at', 'created_at'),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
    
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    base_date: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    calculated_average_days: Mapped[float] = mapped_column(Numeric(10, 2), nullable=False)
    calculated_date: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    total_amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False)
    check_count: Mapped[int] = mapped_column(Integer, nullable=False)
    currency_id: Mapped[int] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False, index=True)
    description: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # روابط
    business = relationship("Business", backref="check_reconciliations")
    currency = relationship("Currency")
    created_by_user = relationship("User")
    items: Mapped[list["CheckReconciliationItem"]] = relationship("CheckReconciliationItem", back_populates="reconciliation", cascade="all, delete-orphan")


class CheckReconciliationItem(Base):
    __tablename__ = "check_reconciliation_items"
    __table_args__ = (
        Index('ix_check_reconciliation_items_reconciliation', 'reconciliation_id'),
        Index('ix_check_reconciliation_items_check', 'check_id'),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    reconciliation_id: Mapped[int] = mapped_column(Integer, ForeignKey("check_reconciliations.id", ondelete="CASCADE"), nullable=False, index=True)
    check_id: Mapped[int] = mapped_column(Integer, ForeignKey("checks.id", ondelete="CASCADE"), nullable=False, index=True)
    
    days_to_maturity: Mapped[int] = mapped_column(Integer, nullable=False)
    weighted_value: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    
    # روابط
    reconciliation: Mapped["CheckReconciliation"] = relationship("CheckReconciliation", back_populates="items")
    check: Mapped["Check"] = relationship("Check", back_populates="reconciliation_items")


