"""رکورد سند اتوماسیون. بایت فایل در FileStorage می‌ماند."""
from __future__ import annotations

from datetime import date, datetime
from typing import Optional

from sqlalchemy import Date, DateTime, ForeignKey, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class OaDocument(Base):
	__tablename__ = "oa_documents"
	__table_args__ = (Index("ix_oa_documents_business_id", "business_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	title: Mapped[str] = mapped_column(String(500), nullable=False)
	confidentiality: Mapped[str] = mapped_column(String(32), nullable=False, default="normal")
	letter_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("oa_letters.id", ondelete="SET NULL"), nullable=True)
	current_version_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
	reference_no: Mapped[Optional[str]] = mapped_column(String(120), nullable=True)
	search_text: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	retain_until: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
	retention_status: Mapped[str] = mapped_column(String(16), nullable=False, default="none")


class OaDocumentVersion(Base):
	__tablename__ = "oa_document_versions"
	__table_args__ = (
		UniqueConstraint("document_id", "version_no", name="uq_oa_document_versions_no"),
		Index("ix_oa_document_versions_document_id", "document_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	document_id: Mapped[int] = mapped_column(Integer, ForeignKey("oa_documents.id", ondelete="CASCADE"), nullable=False)
	version_no: Mapped[int] = mapped_column(Integer, nullable=False)
	file_storage_id: Mapped[str] = mapped_column(String(36), ForeignKey("file_storage.id", ondelete="RESTRICT"), nullable=False)
	extracted_text: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class OaOcrJob(Base):
	__tablename__ = "oa_ocr_jobs"
	__table_args__ = (
		Index("ix_oa_ocr_jobs_status", "status"),
		Index("ix_oa_ocr_jobs_letter_attachment", "letter_attachment_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	document_version_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("oa_document_versions.id", ondelete="CASCADE"), nullable=True)
	letter_attachment_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("oa_letter_attachments.id", ondelete="CASCADE"), nullable=True)
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="queued")
	error: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	finished_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)


class OaExtractionSuggestion(Base):
	__tablename__ = "oa_extraction_suggestions"
	__table_args__ = (Index("ix_oa_extraction_suggestions_document_id", "document_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	document_id: Mapped[int] = mapped_column(Integer, ForeignKey("oa_documents.id", ondelete="CASCADE"), nullable=False)
	version_id: Mapped[int] = mapped_column(Integer, ForeignKey("oa_document_versions.id", ondelete="CASCADE"), nullable=False)
	field_key: Mapped[str] = mapped_column(String(32), nullable=False)
	suggested_value: Mapped[str] = mapped_column(String(500), nullable=False)
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
	confirmed_by_user_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	confirmed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
