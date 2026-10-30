"""
مدل‌های افزونه کنترل اموال و دارایی ثابت.
"""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
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
	text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class FixedAssetSettings(Base):
	__tablename__ = "fa_settings"
	__table_args__ = (UniqueConstraint("business_id", name="uq_fa_settings_business"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	default_currency_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("currencies.id", ondelete="SET NULL"), nullable=True
	)
	vat_account_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True
	)
	vat_output_account_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True
	)
	opening_equity_account_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True
	)
	disposal_gain_account_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True
	)
	disposal_loss_account_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True
	)
	repair_expense_account_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True
	)
	# from_ready_date | next_month
	accounting_convention: Mapped[str] = mapped_column(String(32), nullable=False, default="from_ready_date")
	# ماده ۱۴۹: پس از بیش از N ماه رکود، استهلاک مالیاتی در عامل tax_idle_factor ضرب می‌شود.
	tax_idle_months: Mapped[int] = mapped_column(Integer, nullable=False, default=6)
	tax_idle_factor: Mapped[Decimal] = mapped_column(Numeric(8, 6), nullable=False, default=Decimal("0.7"))
	# استاندارد ۱۱: پیش‌فرض ۱ یعنی رکود استهلاک حسابداری را قطع نمی‌کند.
	accounting_idle_factor: Mapped[Decimal] = mapped_column(Numeric(8, 6), nullable=False, default=Decimal("1"))
	require_custodian: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	plaque_prefix: Mapped[str] = mapped_column(String(16), nullable=False, default="FA")
	extra_settings: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class FixedAssetClass(Base):
	__tablename__ = "fa_classes"
	__table_args__ = (
		UniqueConstraint("business_id", "code", name="uq_fa_classes_biz_code"),
		Index("ix_fa_classes_business_id", "business_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name: Mapped[str] = mapped_column(String(200), nullable=False)
	cost_account_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True
	)
	accum_dep_account_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True
	)
	dep_expense_account_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True
	)
	cost_account_code: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
	accum_dep_account_code: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
	dep_expense_account_code: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
	depreciable: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	default_method: Mapped[str] = mapped_column(String(32), nullable=False, default="straight_line")
	default_useful_life_months: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
	default_declining_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(8, 6), nullable=True)
	tax_table_key: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
	is_system: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)

	assets: Mapped[list["FixedAsset"]] = relationship("FixedAsset", back_populates="asset_class")


class FixedAssetLocation(Base):
	__tablename__ = "fa_locations"
	__table_args__ = (
		UniqueConstraint("business_id", "code", name="uq_fa_locations_biz_code"),
		Index("ix_fa_locations_business_id", "business_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	parent_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("fa_locations.id", ondelete="SET NULL"), nullable=True
	)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name: Mapped[str] = mapped_column(String(200), nullable=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class FixedAsset(Base):
	__tablename__ = "fa_assets"
	__table_args__ = (
		UniqueConstraint("business_id", "code", name="uq_fa_assets_biz_code"),
		Index("ix_fa_assets_business_id", "business_id"),
		Index("ix_fa_assets_class_id", "class_id"),
		Index("ix_fa_assets_status", "status"),
		Index("ix_fa_assets_invoice_id", "invoice_id"),
		Index(
			"uq_fa_assets_invoice_item_line_id",
			"invoice_item_line_id",
			unique=True,
			postgresql_where=text("invoice_item_line_id IS NOT NULL"),
		),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	class_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("fa_classes.id", ondelete="RESTRICT"), nullable=False
	)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name: Mapped[str] = mapped_column(String(255), nullable=False)
	description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	serial_number: Mapped[Optional[str]] = mapped_column(String(128), nullable=True)
	# draft | capitalized | idle | disposed
	status: Mapped[str] = mapped_column(String(32), nullable=False, default="draft")
	idle_from: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
	disposed_at: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
	disposal_kind: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
	disposal_proceeds: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	disposal_document_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True
	)
	sl_monthly_override: Mapped[Optional[Decimal]] = mapped_column(Numeric(18, 8), nullable=True)
	estimate_effective_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
	# purchase | opening
	acquisition_kind: Mapped[str] = mapped_column(String(32), nullable=False, default="purchase")
	acquisition_date: Mapped[date] = mapped_column(Date, nullable=False)
	commission_date: Mapped[date] = mapped_column(Date, nullable=False)
	cost: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
	salvage: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	vat_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	accum_depreciation: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	opening_accum_depreciation: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	method: Mapped[str] = mapped_column(String(32), nullable=False, default="straight_line")
	useful_life_months: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
	declining_annual_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(8, 6), nullable=True)
	location_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("fa_locations.id", ondelete="SET NULL"), nullable=True
	)
	custodian_person_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("persons.id", ondelete="SET NULL"), nullable=True
	)
	project_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("projects.id", ondelete="SET NULL"), nullable=True
	)
	acquisition_document_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True
	)
	invoice_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True
	)
	invoice_item_line_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("invoice_item_lines.id", ondelete="SET NULL"), nullable=True
	)
	extra_info: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
	created_by_user_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)

	asset_class: Mapped["FixedAssetClass"] = relationship("FixedAssetClass", back_populates="assets")


class FixedAssetDocumentLink(Base):
	__tablename__ = "fa_document_links"
	__table_args__ = (
		UniqueConstraint("document_id", name="uq_fa_document_links_document"),
		Index("ix_fa_document_links_asset_id", "asset_id"),
		Index("ix_fa_document_links_run_id", "run_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	asset_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("fa_assets.id", ondelete="SET NULL"), nullable=True
	)
	run_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("fa_depreciation_runs.id", ondelete="SET NULL"), nullable=True
	)
	document_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("documents.id", ondelete="RESTRICT"), nullable=False
	)
	# acquisition | depreciation | disposal | subsequent
	link_type: Mapped[str] = mapped_column(String(32), nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class FixedAssetDepreciationRun(Base):
	__tablename__ = "fa_depreciation_runs"
	__table_args__ = (
		Index("ix_fa_depreciation_runs_business_id", "business_id"),
		Index(
			"uq_fa_depreciation_runs_open_period",
			"business_id",
			"period_year",
			"period_month",
			unique=True,
			postgresql_where=text("status IN ('draft', 'posted')"),
		),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	period_year: Mapped[int] = mapped_column(Integer, nullable=False)
	period_month: Mapped[int] = mapped_column(Integer, nullable=False)
	period_start: Mapped[date] = mapped_column(Date, nullable=False)
	period_end: Mapped[date] = mapped_column(Date, nullable=False)
	# draft | posted | cancelled
	status: Mapped[str] = mapped_column(String(32), nullable=False, default="draft")
	convention: Mapped[str] = mapped_column(String(32), nullable=False)
	total_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	document_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True
	)
	created_by_user_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	posted_by_user_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	posted_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)

	lines: Mapped[list["FixedAssetDepreciationRunLine"]] = relationship(
		"FixedAssetDepreciationRunLine", back_populates="run", cascade="all, delete-orphan"
	)


class FixedAssetDepreciationRunLine(Base):
	__tablename__ = "fa_depreciation_run_lines"
	__table_args__ = (
		UniqueConstraint("run_id", "asset_id", name="uq_fa_depr_run_line_asset"),
		Index("ix_fa_depreciation_run_lines_asset_id", "asset_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	run_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("fa_depreciation_runs.id", ondelete="CASCADE"), nullable=False
	)
	asset_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("fa_assets.id", ondelete="RESTRICT"), nullable=False
	)
	amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
	tax_preview_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	book_value_before: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
	book_value_after: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
	method: Mapped[str] = mapped_column(String(32), nullable=False)
	expense_account_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="RESTRICT"), nullable=False
	)
	accum_account_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="RESTRICT"), nullable=False
	)

	run: Mapped["FixedAssetDepreciationRun"] = relationship(
		"FixedAssetDepreciationRun", back_populates="lines"
	)


class FixedAssetSubsequentExpenditure(Base):
	__tablename__ = "fa_subsequent_expenditures"
	__table_args__ = (Index("ix_fa_subsequent_asset_id", "asset_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	asset_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("fa_assets.id", ondelete="RESTRICT"), nullable=False
	)
	# routine | major
	kind: Mapped[str] = mapped_column(String(32), nullable=False)
	amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
	vat_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	expenditure_date: Mapped[date] = mapped_column(Date, nullable=False)
	document_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("documents.id", ondelete="RESTRICT"), nullable=False
	)
	description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	created_by_user_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class FixedAssetEstimateChange(Base):
	__tablename__ = "fa_estimate_changes"
	__table_args__ = (Index("ix_fa_estimate_changes_asset_id", "asset_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	asset_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("fa_assets.id", ondelete="RESTRICT"), nullable=False
	)
	effective_date: Mapped[date] = mapped_column(Date, nullable=False)
	old_method: Mapped[str] = mapped_column(String(32), nullable=False)
	new_method: Mapped[str] = mapped_column(String(32), nullable=False)
	old_useful_life_months: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
	remaining_useful_life_months: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
	old_declining_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(8, 6), nullable=True)
	new_declining_rate: Mapped[Optional[Decimal]] = mapped_column(Numeric(8, 6), nullable=True)
	old_salvage: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
	new_salvage: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
	sl_monthly_override: Mapped[Optional[Decimal]] = mapped_column(Numeric(18, 8), nullable=True)
	remaining_depreciable: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
	created_by_user_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
