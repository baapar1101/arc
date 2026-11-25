"""تنظیمات افزونه تولید پیشرفته. گزارش‌ها از اسناد هسته خوانده می‌شوند."""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Integer, Numeric, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class AdvancedProductionSettings(Base):
	__tablename__ = "advanced_production_settings"
	__table_args__ = (
		UniqueConstraint("business_id", name="uq_advanced_production_settings_business"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	costing_method: Mapped[str] = mapped_column(String(32), nullable=False, default="actual")
	overhead_mode: Mapped[str] = mapped_column(String(32), nullable=False, default="bom_operations")
	wip_account_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True
	)
	finished_goods_account_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True
	)
	scrap_expense_account_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True
	)
	cost_variance_account_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True
	)
	created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime(timezone=True), nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow
	)


class AdvancedProductionWorkCenter(Base):
	__tablename__ = "ap_work_centers"
	__table_args__ = (UniqueConstraint("business_id", "code", name="uq_ap_work_centers_code"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name: Mapped[str] = mapped_column(String(255), nullable=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)


class AdvancedProductionLine(Base):
	__tablename__ = "ap_lines"
	__table_args__ = (UniqueConstraint("business_id", "code", name="uq_ap_lines_code"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	work_center_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("ap_work_centers.id", ondelete="SET NULL"), nullable=True)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name: Mapped[str] = mapped_column(String(255), nullable=False)
	nominal_units_per_hour: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=0)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)


class AdvancedProductionMachine(Base):
	__tablename__ = "ap_machines"
	__table_args__ = (UniqueConstraint("business_id", "code", name="uq_ap_machines_code"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	line_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("ap_lines.id", ondelete="SET NULL"), nullable=True)
	fixed_asset_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("fa_assets.id", ondelete="SET NULL"), nullable=True)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name: Mapped[str] = mapped_column(String(255), nullable=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)


class AdvancedProductionShift(Base):
	__tablename__ = "ap_shifts"
	__table_args__ = (UniqueConstraint("business_id", "code", name="uq_ap_shifts_code"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name: Mapped[str] = mapped_column(String(255), nullable=False)
	start_time: Mapped[str | None] = mapped_column(String(5), nullable=True)
	end_time: Mapped[str | None] = mapped_column(String(5), nullable=True)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)


class AdvancedProductionDowntime(Base):
	__tablename__ = "ap_downtime"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	line_id: Mapped[int] = mapped_column(Integer, ForeignKey("ap_lines.id", ondelete="CASCADE"), nullable=False, index=True)
	machine_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("ap_machines.id", ondelete="SET NULL"), nullable=True)
	started_on: Mapped[date] = mapped_column(Date, nullable=False)
	ended_on: Mapped[date | None] = mapped_column(Date, nullable=True)
	minutes: Mapped[int] = mapped_column(Integer, nullable=False)
	reason_code: Mapped[str] = mapped_column(String(64), nullable=False)
	cost_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	notes: Mapped[str | None] = mapped_column(Text, nullable=True)


class AdvancedProductionOutputLog(Base):
	__tablename__ = "ap_output_logs"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	line_id: Mapped[int] = mapped_column(Integer, ForeignKey("ap_lines.id", ondelete="CASCADE"), nullable=False, index=True)
	shift_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("ap_shifts.id", ondelete="SET NULL"), nullable=True)
	operator_person_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("persons.id", ondelete="SET NULL"), nullable=True)
	machine_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("ap_machines.id", ondelete="SET NULL"), nullable=True)
	product_id: Mapped[int] = mapped_column(Integer, ForeignKey("products.id", ondelete="RESTRICT"), nullable=False)
	produced_on: Mapped[date] = mapped_column(Date, nullable=False, index=True)
	run_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
	quantity_good: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
	quantity_scrap: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=0)


class AdvancedProductionInspection(Base):
	__tablename__ = "ap_qc_inspections"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	product_id: Mapped[int] = mapped_column(Integer, ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True)
	stage: Mapped[str] = mapped_column(String(16), nullable=False)
	inspected_on: Mapped[date] = mapped_column(Date, nullable=False, index=True)
	quantity_checked: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
	quantity_rejected: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=0)
	result: Mapped[str] = mapped_column(String(16), nullable=False)
	reason_code: Mapped[str | None] = mapped_column(String(64), nullable=True)
	notes: Mapped[str | None] = mapped_column(Text, nullable=True)


class AdvancedProductionMaintenance(Base):
	"""سوابق خرابی و سرویس. مبلغ هزینه عملیاتی است و خودش سند دفتر کل نمی‌سازد."""

	__tablename__ = "ap_maintenance"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	machine_id: Mapped[int] = mapped_column(Integer, ForeignKey("ap_machines.id", ondelete="CASCADE"), nullable=False, index=True)
	line_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("ap_lines.id", ondelete="SET NULL"), nullable=True)
	kind: Mapped[str] = mapped_column(String(16), nullable=False)
	opened_on: Mapped[date] = mapped_column(Date, nullable=False, index=True)
	closed_on: Mapped[date | None] = mapped_column(Date, nullable=True)
	repair_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	cost_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	spare_product_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("products.id", ondelete="SET NULL"), nullable=True)
	spare_quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=0)
	notes: Mapped[str | None] = mapped_column(Text, nullable=True)


class AdvancedProductionScrapReason(Base):
	"""علت ضایعات. قابل‌بازیافت بودن را کاربر ثبت می‌کند."""

	__tablename__ = "ap_scrap_reasons"
	__table_args__ = (UniqueConstraint("business_id", "code", name="uq_ap_scrap_reasons_code"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name: Mapped[str] = mapped_column(String(255), nullable=False)
	recyclable: Mapped[bool] = mapped_column(Boolean, nullable=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)


class AdvancedProductionScrapEvent(Base):
	"""ضایعات ثبت‌شده با علت. این رکورد سند دفتر کل نمی‌سازد."""

	__tablename__ = "ap_scrap_events"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	reason_id: Mapped[int] = mapped_column(Integer, ForeignKey("ap_scrap_reasons.id", ondelete="RESTRICT"), nullable=False, index=True)
	product_id: Mapped[int] = mapped_column(Integer, ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True)
	line_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("ap_lines.id", ondelete="SET NULL"), nullable=True)
	occurred_on: Mapped[date] = mapped_column(Date, nullable=False, index=True)
	quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)


class AdvancedProductionOrderHold(Base):
	"""توقف موقت سفارش. وضعیت هسته سفارش را عوض نمی‌کند."""

	__tablename__ = "ap_order_holds"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	production_order_id: Mapped[int] = mapped_column(Integer, ForeignKey("production_orders.id", ondelete="CASCADE"), nullable=False, index=True)
	held_on: Mapped[date] = mapped_column(Date, nullable=False)
	released_on: Mapped[date | None] = mapped_column(Date, nullable=True)
	reason: Mapped[str] = mapped_column(String(255), nullable=False)


class AdvancedProductionOrderLine(Base):
	"""خط تولیدکننده یک سفارش. برای محاسبه ساعت ظرفیت است و وضعیت هسته را عوض نمی‌کند."""

	__tablename__ = "ap_order_lines"
	__table_args__ = (UniqueConstraint("business_id", "production_order_id", name="uq_ap_order_lines_order"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	production_order_id: Mapped[int] = mapped_column(Integer, ForeignKey("production_orders.id", ondelete="CASCADE"), nullable=False)
	line_id: Mapped[int] = mapped_column(Integer, ForeignKey("ap_lines.id", ondelete="CASCADE"), nullable=False)


class AdvancedProductionWipCount(Base):
	"""شمارش مقداری سفارش باز. با مانده دفتر کل مقایسه نمی‌شود."""

	__tablename__ = "ap_wip_counts"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	production_order_id: Mapped[int] = mapped_column(Integer, ForeignKey("production_orders.id", ondelete="CASCADE"), nullable=False, index=True)
	counted_on: Mapped[date] = mapped_column(Date, nullable=False)
	counted_quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)


class AdvancedProductionRework(Base):
	"""دوباره‌کاری ثبت‌شده. سند حسابداری و سند انبار نمی‌سازد."""

	__tablename__ = "ap_rework"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	product_id: Mapped[int] = mapped_column(Integer, ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True)
	production_order_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("production_orders.id", ondelete="SET NULL"), nullable=True)
	occurred_on: Mapped[date] = mapped_column(Date, nullable=False, index=True)
	quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)


class AdvancedProductionLineReturn(Base):
	"""برگشت مقداری به خط. حواله انبار و سند دفتر کل نمی‌سازد."""

	__tablename__ = "ap_line_returns"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	product_id: Mapped[int] = mapped_column(Integer, ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True)
	line_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("ap_lines.id", ondelete="SET NULL"), nullable=True)
	occurred_on: Mapped[date] = mapped_column(Date, nullable=False, index=True)
	quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)


class AdvancedProductionStageTransfer(Base):
	"""انتقال ثبت‌شده بین دو خط. مسیر استاندارد چندمرحله‌ای و سند انبار نیست."""

	__tablename__ = "ap_stage_transfers"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	from_line_id: Mapped[int] = mapped_column(Integer, ForeignKey("ap_lines.id", ondelete="RESTRICT"), nullable=False)
	to_line_id: Mapped[int] = mapped_column(Integer, ForeignKey("ap_lines.id", ondelete="RESTRICT"), nullable=False)
	product_id: Mapped[int] = mapped_column(Integer, ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True)
	transferred_on: Mapped[date] = mapped_column(Date, nullable=False, index=True)
	quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)


class AdvancedProductionLabor(Base):
	"""ساعت و نرخ دستمزد مستقیم تولید. از حقوق خوانده نمی‌شود و سند دفتر کل نمی‌سازد."""

	__tablename__ = "ap_labor"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	production_order_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("production_orders.id", ondelete="SET NULL"), nullable=True)
	person_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("persons.id", ondelete="SET NULL"), nullable=True)
	worked_on: Mapped[date] = mapped_column(Date, nullable=False, index=True)
	actual_hours: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
	standard_hours: Mapped[Decimal | None] = mapped_column(Numeric(18, 6), nullable=True)
	standard_hourly_rate: Mapped[Decimal | None] = mapped_column(Numeric(18, 6), nullable=True)
	actual_hourly_rate: Mapped[Decimal | None] = mapped_column(Numeric(18, 6), nullable=True)
