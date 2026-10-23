from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class SepidarImportSetting(Base):
    __tablename__ = "sepidar_import_settings"
    __table_args__ = (UniqueConstraint("business_id", name="uq_sepidar_import_settings_business"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    business_id: Mapped[int] = mapped_column(ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
    host: Mapped[str] = mapped_column(String(255), nullable=False)
    port: Mapped[int] = mapped_column(Integer, default=1433, nullable=False)
    database_name: Mapped[str] = mapped_column(String(255), nullable=False)
    username: Mapped[str] = mapped_column(String(255), nullable=False)
    password_encrypted: Mapped[str] = mapped_column(Text, nullable=False)
    enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    native_enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, server_default="false")
    operations_enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, server_default="false")
    plugins_enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, server_default="false")
    native_summary: Mapped[Optional[dict]] = mapped_column(JSONB, nullable=True)
    native_last_error: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    sync_interval_minutes: Mapped[int] = mapped_column(Integer, default=15, nullable=False)
    batch_size: Mapped[int] = mapped_column(Integer, default=500, nullable=False)
    included_schemas: Mapped[Optional[list]] = mapped_column(JSONB, nullable=True)
    included_tables: Mapped[Optional[list]] = mapped_column(JSONB, nullable=True)
    last_started_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    last_success_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    last_error: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class SepidarImportRow(Base):
    __tablename__ = "sepidar_import_rows"
    __table_args__ = (
        UniqueConstraint("business_id", "source_schema", "source_table", "source_key", name="uq_sepidar_import_row_source"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    business_id: Mapped[int] = mapped_column(ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
    source_schema: Mapped[str] = mapped_column(String(128), nullable=False)
    source_table: Mapped[str] = mapped_column(String(128), nullable=False)
    source_key: Mapped[str] = mapped_column(String(1000), nullable=False)
    payload: Mapped[dict] = mapped_column(JSONB, nullable=False)
    content_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false", nullable=False)
    first_seen_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class SepidarImportRun(Base):
    __tablename__ = "sepidar_import_runs"

    id: Mapped[int] = mapped_column(primary_key=True)
    business_id: Mapped[int] = mapped_column(ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
    status: Mapped[str] = mapped_column(String(24), nullable=False, default="running")
    tables_total: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    tables_completed: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    rows_seen: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    rows_changed: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    error: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    started_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    finished_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)


class SepidarNativeMap(Base):
    __tablename__ = "sepidar_native_maps"
    __table_args__ = (UniqueConstraint("business_id", "database_name", "source_table", "source_id", name="uq_sepidar_native_source"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    business_id: Mapped[int] = mapped_column(ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
    database_name: Mapped[str] = mapped_column(String(255), nullable=False)
    source_table: Mapped[str] = mapped_column(String(128), nullable=False)
    source_id: Mapped[str] = mapped_column(String(128), nullable=False)
    target_table: Mapped[str] = mapped_column(String(64), nullable=False)
    target_id: Mapped[int] = mapped_column(Integer, nullable=False)
    source_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
