"""مدل‌های افزونه تدارکات. هویت تأمین‌کننده در persons می‌ماند."""
from __future__ import annotations

from datetime import date, datetime
from typing import Optional

from sqlalchemy import (
	Boolean,
	Date,
	DateTime,
	ForeignKey,
	Index,
	Integer,
	JSON,
	Numeric,
	String,
	Text,
	UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


def _now() -> datetime:
	return datetime.utcnow()


class ProcSettings(Base):
	__tablename__ = "proc_settings"
	__table_args__ = (UniqueConstraint("business_id", name="uq_proc_settings_business"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	mode: Mapped[str] = mapped_column(String(16), nullable=False, default="standard")
	qty_tolerance_pct: Mapped[float] = mapped_column(Numeric(8, 4), nullable=False, default=0)
	price_tolerance: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	budget_required: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	allow_direct_po: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	require_approved_supplier: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	budget_warn_percent: Mapped[int] = mapped_column(Integer, nullable=False, default=80)
	default_approver_user_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	weights: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=_now, onupdate=_now, nullable=False)


class ProcSupplierProfile(Base):
	__tablename__ = "proc_supplier_profiles"
	__table_args__ = (
		UniqueConstraint("business_id", "person_id", name="uq_proc_supplier_person"),
		Index("ix_proc_supplier_business_status", "business_id", "status"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="CASCADE"), nullable=False)
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="prospective")
	category: Mapped[Optional[str]] = mapped_column(String(120), nullable=True)
	payment_terms: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	payment_days: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	risk_score: Mapped[Optional[float]] = mapped_column(Numeric(5, 2), nullable=True)
	notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=_now, onupdate=_now, nullable=False)


class ProcSupplierDocument(Base):
	__tablename__ = "proc_supplier_documents"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	profile_id: Mapped[int] = mapped_column(Integer, ForeignKey("proc_supplier_profiles.id", ondelete="CASCADE"), nullable=False, index=True)
	title: Mapped[str] = mapped_column(String(255), nullable=False)
	doc_type: Mapped[str] = mapped_column(String(64), nullable=False, default="other")
	expires_on: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
	file_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
	notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)


class ProcCostCenter(Base):
	__tablename__ = "proc_cost_centers"
	__table_args__ = (UniqueConstraint("business_id", "code", name="uq_proc_cost_center_code"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name: Mapped[str] = mapped_column(String(255), nullable=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)


class ProcDelegation(Base):
	__tablename__ = "proc_delegations"
	__table_args__ = (Index("ix_proc_delegations_business_user", "business_id", "user_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
	delegate_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
	starts_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)
	ends_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)


class ProcRequisition(Base):
	__tablename__ = "proc_requisitions"
	__table_args__ = (
		UniqueConstraint("business_id", "code", name="uq_proc_requisitions_code"),
		Index("ix_proc_requisitions_business_status", "business_id", "status"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	status: Mapped[str] = mapped_column(String(32), nullable=False, default="draft")
	requester_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
	org_unit_name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	project_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("projects.id", ondelete="SET NULL"), nullable=True)
	cost_center_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("proc_cost_centers.id", ondelete="SET NULL"), nullable=True)
	needed_by: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
	priority: Mapped[str] = mapped_column(String(16), nullable=False, default="normal")
	reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	currency_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="SET NULL"), nullable=True)
	suggested_budget: Mapped[Optional[float]] = mapped_column(Numeric(18, 2), nullable=True)
	source: Mapped[str] = mapped_column(String(32), nullable=False, default="manual")
	duplicate_risk: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	duplicate_ack: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	file_ids: Mapped[Optional[list]] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=_now, onupdate=_now, nullable=False)


class ProcRequisitionLine(Base):
	__tablename__ = "proc_requisition_lines"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	requisition_id: Mapped[int] = mapped_column(Integer, ForeignKey("proc_requisitions.id", ondelete="CASCADE"), nullable=False, index=True)
	product_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("products.id", ondelete="SET NULL"), nullable=True)
	description: Mapped[str] = mapped_column(String(500), nullable=False)
	item_kind: Mapped[str] = mapped_column(String(16), nullable=False, default="goods")
	qty: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False)
	uom: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
	unit_price_estimate: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	warehouse_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
	on_hand_snapshot: Mapped[Optional[float]] = mapped_column(Numeric(18, 6), nullable=True)
	open_po_snapshot: Mapped[Optional[float]] = mapped_column(Numeric(18, 6), nullable=True)
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)


class ProcApproval(Base):
	__tablename__ = "proc_approvals"
	__table_args__ = (Index("ix_proc_approvals_entity", "business_id", "entity_type", "entity_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	entity_type: Mapped[str] = mapped_column(String(32), nullable=False)
	entity_id: Mapped[int] = mapped_column(Integer, nullable=False)
	step_no: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
	approver_user_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	position_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
	note: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	acted_by_user_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	acted_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	is_required: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)


class ProcSourcingEvent(Base):
	__tablename__ = "proc_sourcing_events"
	__table_args__ = (UniqueConstraint("business_id", "code", name="uq_proc_sourcing_code"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	event_type: Mapped[str] = mapped_column(String(16), nullable=False, default="rfq")
	title: Mapped[str] = mapped_column(String(255), nullable=False)
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="draft")
	deadline_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	requisition_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("proc_requisitions.id", ondelete="SET NULL"), nullable=True)
	technical_opened_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	financial_opened_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	award_reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	awarded_invite_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
	minutes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=_now, onupdate=_now, nullable=False)


class ProcSourcingLine(Base):
	__tablename__ = "proc_sourcing_lines"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	event_id: Mapped[int] = mapped_column(Integer, ForeignKey("proc_sourcing_events.id", ondelete="CASCADE"), nullable=False, index=True)
	product_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("products.id", ondelete="SET NULL"), nullable=True)
	description: Mapped[str] = mapped_column(String(500), nullable=False)
	qty: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False)
	uom: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
	item_kind: Mapped[str] = mapped_column(String(16), nullable=False, default="goods")
	warehouse_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
	requisition_line_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)


class ProcSourcingInvite(Base):
	__tablename__ = "proc_sourcing_invites"
	__table_args__ = (UniqueConstraint("event_id", "person_id", name="uq_proc_invite_person"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	event_id: Mapped[int] = mapped_column(Integer, ForeignKey("proc_sourcing_events.id", ondelete="CASCADE"), nullable=False, index=True)
	person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="RESTRICT"), nullable=False)
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="invited")
	reject_reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)


class ProcSourcingBid(Base):
	__tablename__ = "proc_sourcing_bids"
	__table_args__ = (UniqueConstraint("invite_id", name="uq_proc_bid_invite"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	invite_id: Mapped[int] = mapped_column(Integer, ForeignKey("proc_sourcing_invites.id", ondelete="CASCADE"), nullable=False)
	payment_terms: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	payment_days: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	delivery_days: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	warranty: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	freight: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	tax: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	discount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	valid_until: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
	file_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
	technical_score: Mapped[Optional[float]] = mapped_column(Numeric(5, 2), nullable=True)
	note: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	submitted_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)


class ProcSourcingBidLine(Base):
	__tablename__ = "proc_sourcing_bid_lines"
	__table_args__ = (UniqueConstraint("bid_id", "sourcing_line_id", name="uq_proc_bid_line"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	bid_id: Mapped[int] = mapped_column(Integer, ForeignKey("proc_sourcing_bids.id", ondelete="CASCADE"), nullable=False, index=True)
	sourcing_line_id: Mapped[int] = mapped_column(Integer, ForeignKey("proc_sourcing_lines.id", ondelete="CASCADE"), nullable=False)
	unit_price: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False)
	note: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)


class ProcOrder(Base):
	__tablename__ = "proc_orders"
	__table_args__ = (
		UniqueConstraint("business_id", "code", name="uq_proc_orders_code"),
		Index("ix_proc_orders_business_status", "business_id", "status"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	status: Mapped[str] = mapped_column(String(32), nullable=False, default="draft")
	person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="RESTRICT"), nullable=False, index=True)
	requisition_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("proc_requisitions.id", ondelete="SET NULL"), nullable=True)
	sourcing_event_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("proc_sourcing_events.id", ondelete="SET NULL"), nullable=True)
	contract_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("proc_contracts.id", ondelete="SET NULL"), nullable=True)
	budget_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("proc_budgets.id", ondelete="SET NULL"), nullable=True)
	project_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("projects.id", ondelete="SET NULL"), nullable=True)
	cost_center_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("proc_cost_centers.id", ondelete="SET NULL"), nullable=True)
	currency_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="SET NULL"), nullable=True)
	payment_terms: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	delivery_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
	delivery_place: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	warranty: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	freight: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	header_discount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	file_ids: Mapped[Optional[list]] = mapped_column(JSON, nullable=True)
	version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
	supplier_acknowledged_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=_now, onupdate=_now, nullable=False)


class ProcOrderLine(Base):
	__tablename__ = "proc_order_lines"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	order_id: Mapped[int] = mapped_column(Integer, ForeignKey("proc_orders.id", ondelete="CASCADE"), nullable=False, index=True)
	product_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("products.id", ondelete="SET NULL"), nullable=True)
	description: Mapped[str] = mapped_column(String(500), nullable=False)
	item_kind: Mapped[str] = mapped_column(String(16), nullable=False, default="goods")
	qty: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False)
	uom: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
	unit_price: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	discount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	tax: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	warehouse_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
	received_qty: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False, default=0)
	accepted_qty: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False, default=0)
	rejected_qty: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False, default=0)
	invoiced_qty: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False, default=0)
	cancelled_qty: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False, default=0)
	service_confirmed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	requisition_line_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
	contract_line_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)


class ProcReceipt(Base):
	__tablename__ = "proc_receipts"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	order_id: Mapped[int] = mapped_column(Integer, ForeignKey("proc_orders.id", ondelete="CASCADE"), nullable=False, index=True)
	warehouse_document_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True, index=True)
	warehouse_document_ids: Mapped[Optional[list]] = mapped_column(JSON, nullable=True)
	received_on: Mapped[date] = mapped_column(Date, nullable=False)
	note: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)


class ProcReceiptLine(Base):
	__tablename__ = "proc_receipt_lines"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	receipt_id: Mapped[int] = mapped_column(Integer, ForeignKey("proc_receipts.id", ondelete="CASCADE"), nullable=False, index=True)
	order_line_id: Mapped[int] = mapped_column(Integer, ForeignKey("proc_order_lines.id", ondelete="CASCADE"), nullable=False)
	qty: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False)
	rejected_qty: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False, default=0)
	qc_status: Mapped[str] = mapped_column(String(16), nullable=False, default="accept")
	note: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)


class ProcInvoiceLink(Base):
	__tablename__ = "proc_invoice_links"
	__table_args__ = (UniqueConstraint("order_id", "document_id", name="uq_proc_invoice_link"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	order_id: Mapped[int] = mapped_column(Integer, ForeignKey("proc_orders.id", ondelete="CASCADE"), nullable=False, index=True)
	document_id: Mapped[int] = mapped_column(Integer, ForeignKey("documents.id", ondelete="RESTRICT"), nullable=False)
	match_status: Mapped[str] = mapped_column(String(16), nullable=False, default="matched")
	price_variance_accepted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)


class ProcMatchLine(Base):
	__tablename__ = "proc_match_lines"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	link_id: Mapped[int] = mapped_column(Integer, ForeignKey("proc_invoice_links.id", ondelete="CASCADE"), nullable=False, index=True)
	order_line_id: Mapped[int] = mapped_column(Integer, ForeignKey("proc_order_lines.id", ondelete="CASCADE"), nullable=False)
	po_qty: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False)
	receipt_qty: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False)
	invoice_qty: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False)
	po_price: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False)
	invoice_price: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False)
	status: Mapped[str] = mapped_column(String(16), nullable=False)
	reasons: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)


class ProcBudget(Base):
	__tablename__ = "proc_budgets"
	__table_args__ = (Index("ix_proc_budgets_business_period", "business_id", "period_key"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	period_key: Mapped[str] = mapped_column(String(32), nullable=False)
	name: Mapped[str] = mapped_column(String(255), nullable=False)
	amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False)
	org_unit_name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	project_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("projects.id", ondelete="SET NULL"), nullable=True)
	cost_center_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("proc_cost_centers.id", ondelete="SET NULL"), nullable=True)
	fiscal_year_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("fiscal_years.id", ondelete="SET NULL"), nullable=True)
	warn_percent: Mapped[int] = mapped_column(Integer, nullable=False, default=80)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)


class ProcBudgetMovement(Base):
	__tablename__ = "proc_budget_movements"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	budget_id: Mapped[int] = mapped_column(Integer, ForeignKey("proc_budgets.id", ondelete="CASCADE"), nullable=False, index=True)
	counter_budget_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("proc_budgets.id", ondelete="SET NULL"), nullable=True)
	kind: Mapped[str] = mapped_column(String(32), nullable=False)
	amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False)
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
	reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	acted_by_user_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)


class ProcCommitment(Base):
	__tablename__ = "proc_commitments"
	__table_args__ = (UniqueConstraint("order_id", name="uq_proc_commitment_order"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	budget_id: Mapped[int] = mapped_column(Integer, ForeignKey("proc_budgets.id", ondelete="CASCADE"), nullable=False, index=True)
	order_id: Mapped[int] = mapped_column(Integer, ForeignKey("proc_orders.id", ondelete="CASCADE"), nullable=False)
	amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False)
	released_amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)


class ProcContract(Base):
	__tablename__ = "proc_contracts"
	__table_args__ = (UniqueConstraint("business_id", "code", name="uq_proc_contracts_code"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="RESTRICT"), nullable=False)
	title: Mapped[str] = mapped_column(String(255), nullable=False)
	kind: Mapped[str] = mapped_column(String(16), nullable=False, default="blanket")
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="draft")
	start_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
	end_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
	currency_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="SET NULL"), nullable=True)
	ceiling_amount: Mapped[Optional[float]] = mapped_column(Numeric(18, 2), nullable=True)
	payment_terms: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	penalty_note: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	oa_letter_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
	file_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
	last_expiry_notified_on: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
	created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=_now, onupdate=_now, nullable=False)


class ProcContractLine(Base):
	__tablename__ = "proc_contract_lines"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	contract_id: Mapped[int] = mapped_column(Integer, ForeignKey("proc_contracts.id", ondelete="CASCADE"), nullable=False, index=True)
	product_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("products.id", ondelete="SET NULL"), nullable=True)
	description: Mapped[str] = mapped_column(String(500), nullable=False)
	unit_price: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False)
	qty_commitment: Mapped[Optional[float]] = mapped_column(Numeric(18, 6), nullable=True)
	released_qty: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False, default=0)
	discount_percent: Mapped[float] = mapped_column(Numeric(8, 4), nullable=False, default=0)
	warehouse_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)


class ProcGuarantee(Base):
	__tablename__ = "proc_guarantees"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	contract_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("proc_contracts.id", ondelete="CASCADE"), nullable=True)
	order_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("proc_orders.id", ondelete="CASCADE"), nullable=True)
	kind: Mapped[str] = mapped_column(String(64), nullable=False, default="performance")
	amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False)
	due_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
	file_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
	note: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)


class ProcPrepayment(Base):
	__tablename__ = "proc_prepayments"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	order_id: Mapped[int] = mapped_column(Integer, ForeignKey("proc_orders.id", ondelete="CASCADE"), nullable=False, index=True)
	document_id: Mapped[int] = mapped_column(Integer, ForeignKey("documents.id", ondelete="RESTRICT"), nullable=False)
	amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False)
	note: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)


class ProcScore(Base):
	__tablename__ = "proc_scores"
	__table_args__ = (UniqueConstraint("business_id", "person_id", "period_key", name="uq_proc_score_period"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="CASCADE"), nullable=False)
	period_key: Mapped[str] = mapped_column(String(32), nullable=False)
	metrics: Mapped[dict] = mapped_column(JSON, nullable=False)
	weights: Mapped[dict] = mapped_column(JSON, nullable=False)
	total: Mapped[float] = mapped_column(Numeric(6, 2), nullable=False)
	grade: Mapped[str] = mapped_column(String(2), nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)


class ProcShareLink(Base):
	__tablename__ = "proc_share_links"
	__table_args__ = (UniqueConstraint("token_hash", name="uq_proc_share_token"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	token_hash: Mapped[str] = mapped_column(String(64), nullable=False)
	kind: Mapped[str] = mapped_column(String(16), nullable=False)
	entity_id: Mapped[int] = mapped_column(Integer, nullable=False)
	person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="CASCADE"), nullable=False)
	expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	revoked_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)


class ProcPortalInvoice(Base):
	__tablename__ = "proc_portal_invoices"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	order_id: Mapped[int] = mapped_column(Integer, ForeignKey("proc_orders.id", ondelete="CASCADE"), nullable=False, index=True)
	person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="RESTRICT"), nullable=False)
	reference: Mapped[str] = mapped_column(String(120), nullable=False)
	amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False)
	note: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	file_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="received")
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)


class ProcReorderSuggestion(Base):
	__tablename__ = "proc_reorder_suggestions"
	__table_args__ = (Index("ix_proc_reorder_business_status", "business_id", "status"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	product_id: Mapped[int] = mapped_column(Integer, ForeignKey("products.id", ondelete="CASCADE"), nullable=False)
	suggested_qty: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False)
	on_hand: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False, default=0)
	open_qty: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False, default=0)
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="open")
	requisition_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("proc_requisitions.id", ondelete="SET NULL"), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, nullable=False)
