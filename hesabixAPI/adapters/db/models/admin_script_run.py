from __future__ import annotations

from datetime import datetime

from sqlalchemy import String, Integer, DateTime, ForeignKey, Text, JSON, Boolean
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class AdminScriptRun(Base):
	__tablename__ = "admin_script_runs"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	script_key: Mapped[str] = mapped_column(String(120), nullable=False, index=True)
	status: Mapped[str] = mapped_column(String(30), nullable=False, index=True, default="queued")
	dry_run: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")

	# ورودی/خروجی اجرا
	params_json: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	result_json: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	error_text: Mapped[str | None] = mapped_column(Text, nullable=True)

	# آمار
	scanned_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
	updated_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
	skipped_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
	error_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")

	# اجراکننده
	created_by_user_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)

	# زمان‌ها
	started_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	finished_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False, index=True)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	# روابط
	created_by_user = relationship("User")
	logs = relationship("AdminScriptRunLog", back_populates="run", cascade="all, delete-orphan")


class AdminScriptRunLog(Base):
	__tablename__ = "admin_script_run_logs"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	run_id: Mapped[int] = mapped_column(Integer, ForeignKey("admin_script_runs.id", ondelete="CASCADE"), nullable=False, index=True)
	level: Mapped[str] = mapped_column(String(20), nullable=False, default="info")
	message: Mapped[str] = mapped_column(Text, nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False, index=True)

	run = relationship("AdminScriptRun", back_populates="logs")

