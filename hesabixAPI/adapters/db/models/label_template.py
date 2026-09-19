"""ORM models for barcode label templates (plugin: barcode_label_studio)."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Optional

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, JSON
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class LabelTemplate(Base):
	__tablename__ = "label_templates"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True, nullable=False
	)
	name: Mapped[str] = mapped_column(String(160), nullable=False)
	description: Mapped[Optional[str]] = mapped_column(String(512), nullable=True)

	status: Mapped[str] = mapped_column(String(16), default="draft", index=True, nullable=False)
	is_default: Mapped[bool] = mapped_column(Boolean, default=False, index=True, nullable=False)
	version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
	schema_version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)

	design_json: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
	sheet_json: Mapped[Optional[dict[str, Any]]] = mapped_column(JSON, nullable=True)

	created_by: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)
	published_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)


class LabelTemplateRevision(Base):
	__tablename__ = "label_template_revisions"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	template_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("label_templates.id", ondelete="CASCADE"), index=True, nullable=False
	)
	version_no: Mapped[int] = mapped_column(Integer, nullable=False)
	design_json: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
	sheet_json: Mapped[Optional[dict[str, Any]]] = mapped_column(JSON, nullable=True)
	changelog: Mapped[Optional[str]] = mapped_column(String(512), nullable=True)
	created_by: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
