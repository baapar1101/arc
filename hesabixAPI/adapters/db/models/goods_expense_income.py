from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import (
	Date,
	DateTime,
	ForeignKey,
	Integer,
	JSON,
	Numeric,
	String,
	Text,
	UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class GoodsExpenseIncomeDocument(Base):
	"""سند کالای هزینه‌شده / کالای درآمدشده (عملیاتی + مالی)."""

	__tablename__ = "goods_expense_income_documents"
	__table_args__ = (
		UniqueConstraint("business_id", "code", name="uq_gei_docs_business_code"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	fiscal_year_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("fiscal_years.id", ondelete="RESTRICT"), nullable=False, index=True
	)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	document_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
	# goods_expense | goods_income
	doc_kind: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
	# draft_ops | pending_accounting | draft_accounting | posted | cancelled
	status: Mapped[str] = mapped_column(String(32), nullable=False, default="draft_ops", index=True)
	effect_account_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="RESTRICT"), nullable=True, index=True
	)
	person_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("persons.id", ondelete="SET NULL"), nullable=True, index=True
	)
	currency_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False
	)
	description: Mapped[str | None] = mapped_column(Text, nullable=True)
	warehouse_document_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("warehouse_documents.id", ondelete="SET NULL"), nullable=True, index=True
	)
	accounting_document_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True, index=True
	)
	total_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	created_by_user_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
	submitted_by_user_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
	allocated_by_user_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
	posted_by_user_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
	cancelled_by_user_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
	submitted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	allocated_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	posted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	cancelled_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	extra_info: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)

	lines = relationship(
		"GoodsExpenseIncomeLine",
		back_populates="document",
		cascade="all, delete-orphan",
		order_by="GoodsExpenseIncomeLine.line_no",
	)
	effect_account = relationship("Account", foreign_keys=[effect_account_id])
	person = relationship("Person", foreign_keys=[person_id])
	warehouse_document = relationship("WarehouseDocument", foreign_keys=[warehouse_document_id])
	accounting_document = relationship("Document", foreign_keys=[accounting_document_id])

	def touch(self) -> None:
		self.updated_at = datetime.utcnow()


class GoodsExpenseIncomeLine(Base):
	__tablename__ = "goods_expense_income_lines"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	document_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("goods_expense_income_documents.id", ondelete="CASCADE"),
		nullable=False,
		index=True,
	)
	line_no: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
	product_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True
	)
	warehouse_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("warehouses.id", ondelete="RESTRICT"), nullable=False, index=True
	)
	quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
	unit_cost: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))
	amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	description: Mapped[str | None] = mapped_column(Text, nullable=True)
	extra_info: Mapped[dict | None] = mapped_column(JSON, nullable=True)

	document = relationship("GoodsExpenseIncomeDocument", back_populates="lines")
	product = relationship("Product")
	warehouse = relationship("Warehouse")
