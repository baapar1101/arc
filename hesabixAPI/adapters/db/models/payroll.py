"""
مدل‌های دیتابیس افزونه حقوق و دستمزد.

طراحی انعطاف‌پذیر: آیتم‌ها، دسته‌بندی‌ها، پرسنل، دوره، اجرای حقوق و پیوند حسابداری
قابل پیکربندی به ازای هر کسب‌وکار هستند.
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
	SmallInteger,
	String,
	Text,
	UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class PayrollSettings(Base):
	"""تنظیمات حقوق و دستمزد به ازای هر کسب‌وکار."""

	__tablename__ = "payroll_settings"
	__table_args__ = (UniqueConstraint("business_id", name="uq_payroll_settings_business"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("businesses.id", ondelete="CASCADE"),
		nullable=False,
		index=True,
	)
	enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

	# شماره‌گذاری اسناد حقوق
	document_code_format: Mapped[str] = mapped_column(String(20), nullable=False, default="sequential")
	document_code_prefix: Mapped[str] = mapped_column(String(16), nullable=False, default="PAY")

	# حساب‌های پیش‌فرض (اختیاری — هر آیتم می‌تواند حساب جدا داشته باشد)
	wages_payable_account_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True
	)
	payroll_expense_account_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True
	)
	tax_payable_account_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True
	)
	insurance_payable_account_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True
	)

	default_currency_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("currencies.id", ondelete="SET NULL"), nullable=True
	)

	# manual | semi_auto | formula
	calculation_mode: Mapped[str] = mapped_column(String(32), nullable=False, default="manual")
	require_approval: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	auto_post_on_finalize: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	allow_negative_net: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	round_amounts_to: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=0)

	payslip_template_json: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
	extra_settings: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class PayrollItemCategory(Base):
	"""دسته‌بندی آیتم‌های حقوق (مثلاً اضافات، کسورات، مزایای غیرنقدی)."""

	__tablename__ = "payroll_item_categories"
	__table_args__ = (
		UniqueConstraint("business_id", "code", name="uq_payroll_item_categories_biz_code"),
		Index("ix_payroll_item_categories_business_id", "business_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name: Mapped[str] = mapped_column(String(200), nullable=False)
	# earning | deduction | employer_cost | informational
	item_kind: Mapped[str] = mapped_column(String(32), nullable=False, default="earning")
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	is_system: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)

	items: Mapped[list["PayrollItemDefinition"]] = relationship(
		"PayrollItemDefinition", back_populates="category", cascade="all, delete-orphan"
	)


class PayrollItemDefinition(Base):
	"""تعریف آیتم حقوق با نگاشت حساب و قوانین محاسبه."""

	__tablename__ = "payroll_item_definitions"
	__table_args__ = (
		UniqueConstraint("business_id", "code", name="uq_payroll_item_definitions_biz_code"),
		Index("ix_payroll_item_definitions_business_id", "business_id"),
		Index("ix_payroll_item_definitions_category_id", "category_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	category_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("payroll_item_categories.id", ondelete="SET NULL"), nullable=True
	)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name: Mapped[str] = mapped_column(String(200), nullable=False)
	# earning | deduction | employer_cost | informational
	item_kind: Mapped[str] = mapped_column(String(32), nullable=False)

	account_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True
	)
	counter_account_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True
	)

	# manual | fixed | percent_of_base | percent_of_gross | formula
	calculation_type: Mapped[str] = mapped_column(String(32), nullable=False, default="manual")
	default_amount: Mapped[Optional[Decimal]] = mapped_column(Numeric(18, 4), nullable=True)
	percent_value: Mapped[Optional[Decimal]] = mapped_column(Numeric(18, 8), nullable=True)
	formula_expression: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

	affects_gross: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	affects_taxable: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	affects_insurance: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	is_taxable: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	is_insurable: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	show_on_payslip: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	is_system: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	extra_config: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)

	category: Mapped[Optional["PayrollItemCategory"]] = relationship(
		"PayrollItemCategory", back_populates="items"
	)


class PayrollDepartment(Base):
	"""واحد سازمانی / بخش."""

	__tablename__ = "payroll_departments"
	__table_args__ = (
		UniqueConstraint("business_id", "code", name="uq_payroll_departments_biz_code"),
		Index("ix_payroll_departments_business_id", "business_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	parent_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("payroll_departments.id", ondelete="SET NULL"), nullable=True
	)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name: Mapped[str] = mapped_column(String(200), nullable=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class PayrollEmployee(Base):
	"""پروفایل پرسنلی مرتبط با Person."""

	__tablename__ = "payroll_employees"
	__table_args__ = (
		UniqueConstraint("business_id", "person_id", name="uq_payroll_employees_biz_person"),
		UniqueConstraint("business_id", "employee_code", name="uq_payroll_employees_biz_code"),
		Index("ix_payroll_employees_business_id", "business_id"),
		Index("ix_payroll_employees_person_id", "person_id"),
		Index("ix_payroll_employees_department_id", "department_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	person_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("persons.id", ondelete="CASCADE"), nullable=False
	)
	department_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("payroll_departments.id", ondelete="SET NULL"), nullable=True
	)
	employee_code: Mapped[str] = mapped_column(String(64), nullable=False)
	job_title: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
	# full_time | part_time | contract | daily | seasonal
	employment_type: Mapped[str] = mapped_column(String(32), nullable=False, default="full_time")
	hire_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
	termination_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
	base_salary: Mapped[Optional[Decimal]] = mapped_column(Numeric(18, 4), nullable=True)
	insurance_number: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
	tax_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
	bank_account_info: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	extra_info: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class PayrollPeriod(Base):
	"""دوره حقوق (معمولاً ماهانه)."""

	__tablename__ = "payroll_periods"
	__table_args__ = (
		UniqueConstraint("business_id", "year", "month", name="uq_payroll_periods_biz_year_month"),
		Index("ix_payroll_periods_business_id", "business_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	year: Mapped[int] = mapped_column(SmallInteger, nullable=False)
	month: Mapped[int] = mapped_column(SmallInteger, nullable=False)
	title: Mapped[str] = mapped_column(String(120), nullable=False)
	start_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
	end_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
	# open | closed
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="open")
	closed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	closed_by_user_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class PayrollRun(Base):
	"""اجرای حقوق / سند حقوق تجمیعی."""

	__tablename__ = "payroll_runs"
	__table_args__ = (
		UniqueConstraint("business_id", "code", name="uq_payroll_runs_biz_code"),
		Index("ix_payroll_runs_business_id", "business_id"),
		Index("ix_payroll_runs_period_id", "period_id"),
		Index("ix_payroll_runs_status", "status"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	period_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("payroll_periods.id", ondelete="SET NULL"), nullable=True
	)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	title: Mapped[str] = mapped_column(String(200), nullable=False)
	run_date: Mapped[date] = mapped_column(Date, nullable=False)
	description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

	# draft | pending_approval | approved | finalized | posted | cancelled
	status: Mapped[str] = mapped_column(String(32), nullable=False, default="draft")

	gross_total: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False, default=Decimal("0"))
	deduction_total: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False, default=Decimal("0"))
	net_total: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False, default=Decimal("0"))
	employer_cost_total: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False, default=Decimal("0"))

	created_by_user_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	approved_by_user_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	finalized_by_user_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	posted_by_user_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	approved_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	finalized_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	posted_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	cancelled_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)

	extra_info: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)

	lines: Mapped[list["PayrollRunLine"]] = relationship(
		"PayrollRunLine", back_populates="run", cascade="all, delete-orphan"
	)
	document_links: Mapped[list["PayrollDocumentLink"]] = relationship(
		"PayrollDocumentLink", back_populates="run", cascade="all, delete-orphan"
	)


class PayrollRunLine(Base):
	"""ردیف حقوق هر پرسنل در یک اجرا."""

	__tablename__ = "payroll_run_lines"
	__table_args__ = (
		UniqueConstraint("run_id", "employee_id", name="uq_payroll_run_lines_run_employee"),
		Index("ix_payroll_run_lines_run_id", "run_id"),
		Index("ix_payroll_run_lines_employee_id", "employee_id"),
		Index("ix_payroll_run_lines_person_id", "person_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	run_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("payroll_runs.id", ondelete="CASCADE"), nullable=False
	)
	employee_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("payroll_employees.id", ondelete="RESTRICT"), nullable=False
	)
	person_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("persons.id", ondelete="RESTRICT"), nullable=False
	)
	line_number: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
	notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

	gross_amount: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False, default=Decimal("0"))
	deduction_amount: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False, default=Decimal("0"))
	net_amount: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False, default=Decimal("0"))
	employer_cost_amount: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False, default=Decimal("0"))

	run: Mapped["PayrollRun"] = relationship("PayrollRun", back_populates="lines")
	items: Mapped[list["PayrollRunLineItem"]] = relationship(
		"PayrollRunLineItem", back_populates="run_line", cascade="all, delete-orphan"
	)


class PayrollRunLineItem(Base):
	"""مقدار هر آیتم حقوق در ردیف پرسنل."""

	__tablename__ = "payroll_run_line_items"
	__table_args__ = (
		UniqueConstraint("run_line_id", "item_definition_id", name="uq_payroll_run_line_items_line_item"),
		Index("ix_payroll_run_line_items_run_line_id", "run_line_id"),
		Index("ix_payroll_run_line_items_item_definition_id", "item_definition_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	run_line_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("payroll_run_lines.id", ondelete="CASCADE"), nullable=False
	)
	item_definition_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("payroll_item_definitions.id", ondelete="RESTRICT"), nullable=False
	)
	amount: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False, default=Decimal("0"))
	quantity: Mapped[Optional[Decimal]] = mapped_column(Numeric(18, 6), nullable=True)
	is_computed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

	run_line: Mapped["PayrollRunLine"] = relationship("PayrollRunLine", back_populates="items")


class PayrollDocumentLink(Base):
	"""پیوند اجرای حقوق با سند حسابداری."""

	__tablename__ = "payroll_document_links"
	__table_args__ = (
		Index("ix_payroll_document_links_run_id", "run_id"),
		Index("ix_payroll_document_links_document_id", "document_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	run_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("payroll_runs.id", ondelete="CASCADE"), nullable=False
	)
	document_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("documents.id", ondelete="CASCADE"), nullable=False
	)
	# accrual | payment | reversal
	link_type: Mapped[str] = mapped_column(String(32), nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)

	run: Mapped["PayrollRun"] = relationship("PayrollRun", back_populates="document_links")


class PayrollAuditLog(Base):
	"""لاگ تغییرات برای حسابرسی."""

	__tablename__ = "payroll_audit_logs"
	__table_args__ = (Index("ix_payroll_audit_logs_business_entity", "business_id", "entity_type", "entity_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	entity_type: Mapped[str] = mapped_column(String(64), nullable=False)
	entity_id: Mapped[int] = mapped_column(Integer, nullable=False)
	action: Mapped[str] = mapped_column(String(64), nullable=False)
	user_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	old_values: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
	new_values: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
