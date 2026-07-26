"""مدل‌های گزارش سفارشی HScript."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, JSON, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base
from app.core.datetime_utils import utc_now_aware


class HScriptReport(Base):
	"""تعریف گزارش اسکریپتی متعلق به یک کسب‌وکار."""

	__tablename__ = "hscript_reports"
	__table_args__ = (
		UniqueConstraint("business_id", "slug", name="uq_hscript_reports_business_slug"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	slug: Mapped[str] = mapped_column(String(80), nullable=False)
	title: Mapped[str] = mapped_column(String(255), nullable=False)
	description: Mapped[str | None] = mapped_column(Text, nullable=True)
	# draft | published | archived
	status: Mapped[str] = mapped_column(String(32), nullable=False, default="draft", index=True)
	# source of currently active/published version content is denormalized for quick list
	source_code: Mapped[str] = mapped_column(Text, nullable=False, default="")
	source_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
	language_version: Mapped[str] = mapped_column(String(16), nullable=False, default="1.0.0")
	default_params: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	created_by_user_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	updated_by_user_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
	is_deleted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, index=True)
	created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now_aware, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime(timezone=True), default=utc_now_aware, onupdate=utc_now_aware, nullable=False
	)


class HScriptReportVersion(Base):
	"""نسخه‌های immutable اسکریپت."""

	__tablename__ = "hscript_report_versions"
	__table_args__ = (
		UniqueConstraint("report_id", "version_no", name="uq_hscript_report_versions_no"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	report_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("hscript_reports.id", ondelete="CASCADE"), nullable=False, index=True
	)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	version_no: Mapped[int] = mapped_column(Integer, nullable=False)
	source_code: Mapped[str] = mapped_column(Text, nullable=False)
	source_hash: Mapped[str] = mapped_column(String(64), nullable=False)
	language_version: Mapped[str] = mapped_column(String(16), nullable=False, default="1.0.0")
	changelog: Mapped[str | None] = mapped_column(Text, nullable=True)
	created_by_user_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now_aware, nullable=False)


class HScriptReportRun(Base):
	"""سابقه اجرای گزارش (audit + نتیجه)."""

	__tablename__ = "hscript_report_runs"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	report_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("hscript_reports.id", ondelete="SET NULL"), nullable=True, index=True
	)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	version_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("hscript_report_versions.id", ondelete="SET NULL"), nullable=True
	)
	ran_by_user_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	# success | error
	status: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
	is_preview: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	source_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
	params: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	result_spec: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	error: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	stats: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	duration_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now_aware, nullable=False)


class HScriptReportSchedule(Base):
	"""زمان‌بندی اجرای خودکار گزارش منتشرشده و تحویل خروجی."""

	__tablename__ = "hscript_report_schedules"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	report_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("hscript_reports.id", ondelete="CASCADE"), nullable=False, index=True
	)
	title: Mapped[str] = mapped_column(String(255), nullable=False, default="")
	enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, index=True)
	# simple | cron
	schedule_mode: Mapped[str] = mapped_column(String(32), nullable=False, default="simple")
	# برای mode=simple: daily|weekly|every_hours
	simple_repeat: Mapped[str | None] = mapped_column(String(32), nullable=True, default="daily")
	simple_time: Mapped[str | None] = mapped_column(String(8), nullable=True, default="08:00")
	simple_weekday: Mapped[int | None] = mapped_column(Integer, nullable=True, default=0)
	simple_interval: Mapped[int | None] = mapped_column(Integer, nullable=True, default=1)
	cron_expression: Mapped[str | None] = mapped_column(String(120), nullable=True)
	timezone: Mapped[str] = mapped_column(String(64), nullable=False, default="Asia/Tehran")
	# pdf | excel | none (فقط اعلان)
	output_format: Mapped[str] = mapped_column(String(16), nullable=False, default="pdf")
	# کانال‌ها: ["inapp","email"]
	channels: Mapped[list | None] = mapped_column(JSON, nullable=True)
	# لیست user_id گیرنده‌ها؛ خالی = سازنده زمان‌بندی
	recipient_user_ids: Mapped[list | None] = mapped_column(JSON, nullable=True)
	params: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	next_run_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
	last_run_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
	last_run_status: Mapped[str | None] = mapped_column(String(32), nullable=True)
	last_run_message: Mapped[str | None] = mapped_column(Text, nullable=True)
	created_by_user_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	updated_by_user_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now_aware, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime(timezone=True), default=utc_now_aware, onupdate=utc_now_aware, nullable=False
	)
