from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import String, Integer, DateTime, ForeignKey, Text, Numeric, UniqueConstraint, Date, JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class ReceivedLoanFacility(Base):
	"""قرارداد تسهیلات دریافتی (حقوق بدهنده / بدهی کسب‌وکار)."""

	__tablename__ = "received_loan_facilities"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	currency_id: Mapped[int] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False)
	created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)

	title: Mapped[str] = mapped_column(String(255), nullable=False)
	notes: Mapped[str | None] = mapped_column(Text, nullable=True)
	lender_bank_account_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("bank_accounts.id", ondelete="SET NULL"), nullable=True, index=True)

	principal_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
	annual_interest_rate_percent: Mapped[Decimal | None] = mapped_column(Numeric(18, 6), nullable=True)
	contract_date: Mapped[date] = mapped_column(Date, nullable=False)
	first_installment_date: Mapped[date | None] = mapped_column(Date, nullable=True)
	installment_count: Mapped[int | None] = mapped_column(Integer, nullable=True)

	status: Mapped[str] = mapped_column(String(20), nullable=False, default="draft", server_default="draft")
	schedule_method: Mapped[str | None] = mapped_column(String(40), nullable=True)
	disbursement_document_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True, index=True)
	extra_info: Mapped[dict | None] = mapped_column(JSON, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	installments = relationship(
		"ReceivedLoanInstallment",
		back_populates="facility",
		cascade="all, delete-orphan",
		order_by="ReceivedLoanInstallment.sequence_no",
	)


class ReceivedLoanInstallment(Base):
	__tablename__ = "received_loan_installments"
	__table_args__ = (
		UniqueConstraint("facility_id", "sequence_no", name="uq_received_loan_installments_facility_sequence"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	facility_id: Mapped[int] = mapped_column(Integer, ForeignKey("received_loan_facilities.id", ondelete="CASCADE"), nullable=False, index=True)
	sequence_no: Mapped[int] = mapped_column(Integer, nullable=False)
	due_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)

	principal_due: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	interest_due: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	penalty_due: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))

	principal_paid: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	interest_paid: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	penalty_paid: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))

	extra_info: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	facility = relationship("ReceivedLoanFacility", back_populates="installments")
	payments = relationship(
		"ReceivedLoanInstallmentPayment",
		back_populates="installment",
		cascade="all, delete-orphan",
	)


class ReceivedLoanInstallmentPayment(Base):
	__tablename__ = "received_loan_installment_payments"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	installment_id: Mapped[int] = mapped_column(Integer, ForeignKey("received_loan_installments.id", ondelete="CASCADE"), nullable=False)
	payment_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
	amount_total: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)

	principal_part: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	interest_part: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	penalty_part: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))

	bank_account_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("bank_accounts.id", ondelete="SET NULL"), nullable=True, index=True)
	document_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True, index=True)
	description: Mapped[str | None] = mapped_column(Text, nullable=True)
	created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
	extra_info: Mapped[dict | None] = mapped_column(JSON, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)

	installment = relationship("ReceivedLoanInstallment", back_populates="payments")
