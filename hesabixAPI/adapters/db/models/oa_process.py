"""فرآیند انسانی اتوماسیون اداری، جدا از موتور ورک‌فلو رویدادی."""
from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, Index, Integer, JSON, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class OaProcessDefinition(Base):
	__tablename__ = "oa_process_definitions"
	__table_args__ = (
		UniqueConstraint("business_id", "code", name="uq_oa_process_definitions_code"),
		Index("ix_oa_process_definitions_business_id", "business_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name_i18n: Mapped[dict] = mapped_column(JSON, nullable=False)
	graph: Mapped[dict] = mapped_column(JSON, nullable=False)
	created_by_user_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class OaProcessVersion(Base):
	__tablename__ = "oa_process_versions"
	__table_args__ = (
		UniqueConstraint("definition_id", "version_no", name="uq_oa_process_versions_no"),
		Index("ix_oa_process_versions_business_id", "business_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	definition_id: Mapped[int] = mapped_column(Integer, ForeignKey("oa_process_definitions.id", ondelete="CASCADE"), nullable=False)
	version_no: Mapped[int] = mapped_column(Integer, nullable=False)
	graph: Mapped[dict] = mapped_column(JSON, nullable=False)
	published_by_user_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	published_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class OaProcessInstance(Base):
	__tablename__ = "oa_process_instances"
	__table_args__ = (Index("ix_oa_process_instances_business_id", "business_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	version_id: Mapped[int] = mapped_column(Integer, ForeignKey("oa_process_versions.id", ondelete="RESTRICT"), nullable=False)
	graph_snapshot: Mapped[dict] = mapped_column(JSON, nullable=False)
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="running")
	variables: Mapped[dict] = mapped_column(JSON, nullable=False)
	started_by_user_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	started_by_position_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("oa_positions.id", ondelete="SET NULL"), nullable=True)
	parent_instance_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("oa_process_instances.id", ondelete="SET NULL"), nullable=True)
	started_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)


class OaProcessToken(Base):
	__tablename__ = "oa_process_tokens"
	__table_args__ = (Index("ix_oa_process_tokens_instance_id", "instance_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	instance_id: Mapped[int] = mapped_column(Integer, ForeignKey("oa_process_instances.id", ondelete="CASCADE"), nullable=False)
	node_id: Mapped[str] = mapped_column(String(64), nullable=False)
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="waiting")
	wait_kind: Mapped[Optional[str]] = mapped_column(String(16), nullable=True)
	resume_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	child_instance_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("oa_process_instances.id", ondelete="SET NULL"), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class OaProcessTask(Base):
	__tablename__ = "oa_process_tasks"
	__table_args__ = (
		Index("ix_oa_process_tasks_business_position", "business_id", "assignee_position_id"),
		Index("ix_oa_process_tasks_instance_id", "instance_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	instance_id: Mapped[int] = mapped_column(Integer, ForeignKey("oa_process_instances.id", ondelete="CASCADE"), nullable=False)
	token_id: Mapped[int] = mapped_column(Integer, ForeignKey("oa_process_tokens.id", ondelete="CASCADE"), nullable=False)
	node_id: Mapped[str] = mapped_column(String(64), nullable=False)
	name: Mapped[str] = mapped_column(String(200), nullable=False)
	assignee_position_id: Mapped[int] = mapped_column(Integer, ForeignKey("oa_positions.id", ondelete="RESTRICT"), nullable=False)
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="open")
	form_schema: Mapped[list] = mapped_column(JSON, nullable=False)
	form_data: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
	due_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	escalated_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	completed_by_user_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	note: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
