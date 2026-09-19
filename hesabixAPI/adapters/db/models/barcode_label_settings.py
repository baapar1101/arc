"""Per-business barcode label plugin settings (printer profiles, etc.)."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, Integer, JSON
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class BarcodeLabelSettings(Base):
	__tablename__ = "barcode_label_settings"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), unique=True, index=True, nullable=False
	)
	settings_json: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False, default=dict)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)
