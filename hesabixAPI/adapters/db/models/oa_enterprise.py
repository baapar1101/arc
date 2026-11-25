"""شعبه، نگهداری و درخواست امضای ارائه‌دهنده. تصویر امضا در این جدول نیست."""
from __future__ import annotations

from datetime import date, datetime
from typing import Optional

from sqlalchemy import Date, DateTime, ForeignKey, Index, Integer, JSON, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class OaBranch(Base):
	__tablename__ = "oa_branches"
	__table_args__ = (UniqueConstraint("business_id", "code", name="uq_oa_branches_biz_code"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name_i18n: Mapped[dict] = mapped_column(JSON, nullable=False)
	is_active: Mapped[bool] = mapped_column(nullable=False, default=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class OaRetentionPolicy(Base):
	__tablename__ = "oa_retention_policies"
	__table_args__ = (UniqueConstraint("business_id", "confidentiality", name="uq_oa_retention_policy"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	confidentiality: Mapped[str] = mapped_column(String(32), nullable=False)
	retain_days: Mapped[int] = mapped_column(Integer, nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class OaSignatureProvider(Base):
	__tablename__ = "oa_signature_providers"
	__table_args__ = (UniqueConstraint("business_id", "code", name="uq_oa_signature_providers"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name: Mapped[str] = mapped_column(String(160), nullable=False)
	endpoint_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
	access_token: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
	is_active: Mapped[bool] = mapped_column(nullable=False, default=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class OaQualifiedSignRequest(Base):
	__tablename__ = "oa_qualified_sign_requests"
	__table_args__ = (Index("ix_oa_qualified_sign_letter", "letter_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	letter_id: Mapped[int] = mapped_column(Integer, ForeignKey("oa_letters.id", ondelete="CASCADE"), nullable=False)
	provider_id: Mapped[int] = mapped_column(Integer, ForeignKey("oa_signature_providers.id", ondelete="RESTRICT"), nullable=False)
	requested_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
	status: Mapped[str] = mapped_column(String(24), nullable=False, default="awaiting_provider")
	external_ref: Mapped[Optional[str]] = mapped_column(String(120), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
	completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)


class OaLetterCommercialLink(Base):
	__tablename__ = "oa_letter_commercial_links"
	__table_args__ = (
		UniqueConstraint("letter_id", "target_kind", "target_id", name="uq_oa_letter_commercial_target"),
		Index("ix_oa_letter_commercial_letter", "letter_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	letter_id: Mapped[int] = mapped_column(Integer, ForeignKey("oa_letters.id", ondelete="CASCADE"), nullable=False)
	target_kind: Mapped[str] = mapped_column(String(16), nullable=False)
	target_id: Mapped[int] = mapped_column(Integer, nullable=False)
	created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class OaLetterExchange(Base):
	__tablename__ = "oa_letter_exchanges"
	__table_args__ = (Index("ix_oa_letter_exchanges_source", "source_business_id", "source_letter_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	source_business_id: Mapped[int] = mapped_column(Integer, nullable=False)
	source_letter_id: Mapped[int] = mapped_column(Integer, ForeignKey("oa_letters.id", ondelete="RESTRICT"), nullable=False)
	target_business_id: Mapped[int] = mapped_column(Integer, nullable=False)
	target_letter_id: Mapped[int] = mapped_column(Integer, ForeignKey("oa_letters.id", ondelete="RESTRICT"), nullable=False)
	created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
