"""مدل‌های افزونه اتوماسیون اداری سمت‌محور."""
from __future__ import annotations

from datetime import date, datetime
from typing import Optional

from sqlalchemy import (
	Boolean,
	Date,
	DateTime,
	ForeignKey,
	Index,
	Integer,
	JSON,
	String,
	Text,
	UniqueConstraint,
	text,
)
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class OaSettings(Base):
	__tablename__ = "oa_settings"
	__table_args__ = (UniqueConstraint("business_id", name="uq_oa_settings_business"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	numbering_calendar: Mapped[str] = mapped_column(String(16), nullable=False, default="jalali")
	incoming_prefix: Mapped[str] = mapped_column(String(16), nullable=False, default="IN")
	outgoing_prefix: Mapped[str] = mapped_column(String(16), nullable=False, default="OUT")
	internal_prefix: Mapped[str] = mapped_column(String(16), nullable=False, default="INT")
	letterhead_file_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
	background_file_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
	footer_text: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	paper_size: Mapped[str] = mapped_column(String(16), nullable=False, default="a4")
	paper_orientation: Mapped[str] = mapped_column(String(16), nullable=False, default="portrait")
	margin_top: Mapped[int] = mapped_column(Integer, nullable=False, default=20)
	margin_right: Mapped[int] = mapped_column(Integer, nullable=False, default=20)
	margin_bottom: Mapped[int] = mapped_column(Integer, nullable=False, default=20)
	margin_left: Mapped[int] = mapped_column(Integer, nullable=False, default=20)
	default_body_format: Mapped[str] = mapped_column(String(16), nullable=False, default="markdown")
	default_format_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
	extra_settings: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class OaOrgUnit(Base):
	__tablename__ = "oa_org_units"
	__table_args__ = (
		UniqueConstraint("business_id", "code", name="uq_oa_org_units_biz_code"),
		Index("ix_oa_org_units_business_id", "business_id"),
		Index("ix_oa_org_units_parent_id", "parent_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	parent_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_org_units.id", ondelete="SET NULL"), nullable=True
	)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name_i18n: Mapped[dict] = mapped_column(JSON, nullable=False)
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class OaPosition(Base):
	__tablename__ = "oa_positions"
	__table_args__ = (
		UniqueConstraint("business_id", "code", name="uq_oa_positions_biz_code"),
		Index("ix_oa_positions_business_id", "business_id"),
		Index("ix_oa_positions_org_unit_id", "org_unit_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	org_unit_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_org_units.id", ondelete="RESTRICT"), nullable=False
	)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name_i18n: Mapped[dict] = mapped_column(JSON, nullable=False)
	is_secretariat: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	secretariat_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_secretariats.id", ondelete="SET NULL"), nullable=True, index=True
	)
	can_view_subtree: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class OaPositionHolder(Base):
	__tablename__ = "oa_position_holders"
	__table_args__ = (
		Index("ix_oa_position_holders_business_id", "business_id"),
		Index("ix_oa_position_holders_position_id", "position_id"),
		Index("ix_oa_position_holders_user_id", "user_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	position_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_positions.id", ondelete="CASCADE"), nullable=False
	)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
	starts_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow)
	ends_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	is_primary: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class OaDelegation(Base):
	__tablename__ = "oa_delegations"
	__table_args__ = (
		Index("ix_oa_delegations_business_id", "business_id"),
		Index("ix_oa_delegations_position_id", "position_id"),
		Index("ix_oa_delegations_delegate_user_id", "delegate_user_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	position_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_positions.id", ondelete="CASCADE"), nullable=False
	)
	delegate_user_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
	)
	created_by_user_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
	)
	scope: Mapped[str] = mapped_column(String(16), nullable=False, default="full")
	starts_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow)
	ends_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class OaLetterFormat(Base):
	__tablename__ = "oa_letter_formats"
	__table_args__ = (Index("ix_oa_letter_formats_business_id", "business_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	name: Mapped[str] = mapped_column(String(120), nullable=False)
	paper_size: Mapped[str] = mapped_column(String(16), nullable=False, default="a4")
	paper_orientation: Mapped[str] = mapped_column(String(16), nullable=False, default="portrait")
	margin_top: Mapped[int] = mapped_column(Integer, nullable=False, default=20)
	margin_right: Mapped[int] = mapped_column(Integer, nullable=False, default=20)
	margin_bottom: Mapped[int] = mapped_column(Integer, nullable=False, default=20)
	margin_left: Mapped[int] = mapped_column(Integer, nullable=False, default=20)
	letterhead_file_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
	background_file_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
	footer_text: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	header_html: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	is_default: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class OaLetterTemplate(Base):
	__tablename__ = "oa_letter_templates"
	__table_args__ = (Index("ix_oa_letter_templates_business_id", "business_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	name: Mapped[str] = mapped_column(String(120), nullable=False)
	letter_kind: Mapped[Optional[str]] = mapped_column(String(16), nullable=True)
	subject: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
	body: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	body_format: Mapped[str] = mapped_column(String(16), nullable=False, default="markdown")
	format_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_letter_formats.id", ondelete="SET NULL"), nullable=True
	)
	is_default: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class OaLetter(Base):
	__tablename__ = "oa_letters"
	__table_args__ = (
		Index("ix_oa_letters_business_id", "business_id"),
		Index("ix_oa_letters_status", "business_id", "status"),
		Index("ix_oa_letters_kind", "business_id", "letter_kind"),
		Index("ix_oa_letters_origin_position_id", "origin_position_id"),
		Index(
			"uq_oa_letters_number",
			"business_id",
			"secretariat_id",
			"letter_kind",
			"secretariat_year",
			"secretariat_seq",
			unique=True,
			postgresql_where=text("secretariat_seq IS NOT NULL"),
			sqlite_where=text("secretariat_seq IS NOT NULL"),
		),
		Index("ix_oa_letters_tracking_token", "tracking_token", unique=True),
		Index("ix_oa_letters_secretariat_id", "secretariat_id"),
		Index("ix_oa_letters_archive_folder_id", "archive_folder_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	letter_kind: Mapped[str] = mapped_column(String(16), nullable=False, default="internal")
	status: Mapped[str] = mapped_column(String(24), nullable=False, default="draft")
	subject: Mapped[str] = mapped_column(String(500), nullable=False)
	body: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	body_format: Mapped[str] = mapped_column(String(16), nullable=False, default="markdown")
	locale: Mapped[str] = mapped_column(String(8), nullable=False, default="fa")
	letter_date: Mapped[date] = mapped_column(Date, nullable=False)
	urgency: Mapped[str] = mapped_column(String(16), nullable=False, default="normal")
	confidentiality: Mapped[str] = mapped_column(String(16), nullable=False, default="normal")
	sender_name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	sender_org: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	receiver_name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	receiver_org: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	sender_position_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_positions.id", ondelete="SET NULL"), nullable=True
	)
	receiver_position_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_positions.id", ondelete="SET NULL"), nullable=True
	)
	format_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_letter_formats.id", ondelete="SET NULL"), nullable=True
	)
	template_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_letter_templates.id", ondelete="SET NULL"), nullable=True
	)
	origin_position_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_positions.id", ondelete="RESTRICT"), nullable=False
	)
	created_by_user_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
	)
	registered_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	registered_by_user_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	registered_by_position_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_positions.id", ondelete="SET NULL"), nullable=True
	)
	secretariat_number: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
	secretariat_year: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
	secretariat_seq: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
	follow_up_at: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
	person_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("persons.id", ondelete="SET NULL"), nullable=True
	)
	secretariat_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_secretariats.id", ondelete="SET NULL"), nullable=True
	)
	external_org_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_external_orgs.id", ondelete="SET NULL"), nullable=True
	)
	archive_folder_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_archive_folders.id", ondelete="SET NULL"), nullable=True
	)
	tracking_token: Mapped[Optional[str]] = mapped_column(String(48), nullable=True)
	receipt_number: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
	receipt_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
	sign_status: Mapped[str] = mapped_column(String(16), nullable=False, default="none")
	branch_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
	retain_until: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
	retention_status: Mapped[str] = mapped_column(String(16), nullable=False, default="none")
	qualified_sign_status: Mapped[str] = mapped_column(String(16), nullable=False, default="none")
	keywords: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
	search_text: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	ocr_text: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	ai_summary: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	extra_info: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class OaLetterNumberCounter(Base):
	__tablename__ = "oa_letter_number_counters"
	__table_args__ = (
		UniqueConstraint(
			"business_id", "letter_kind", "year", "secretariat_id", name="uq_oa_letter_counters"
		),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	letter_kind: Mapped[str] = mapped_column(String(16), nullable=False)
	year: Mapped[int] = mapped_column(Integer, nullable=False)
	secretariat_id: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	last_seq: Mapped[int] = mapped_column(Integer, nullable=False, default=0)


class OaReferral(Base):
	__tablename__ = "oa_referrals"
	__table_args__ = (
		Index("ix_oa_referrals_letter_id", "letter_id"),
		Index("ix_oa_referrals_to_position_id", "to_position_id", "status"),
		Index("ix_oa_referrals_from_position_id", "from_position_id"),
		Index("ix_oa_referrals_business_id", "business_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	letter_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_letters.id", ondelete="CASCADE"), nullable=False
	)
	from_position_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_positions.id", ondelete="RESTRICT"), nullable=False
	)
	to_position_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_positions.id", ondelete="RESTRICT"), nullable=False
	)
	from_user_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
	)
	parent_referral_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_referrals.id", ondelete="SET NULL"), nullable=True
	)
	kind: Mapped[str] = mapped_column(String(16), nullable=False, default="action")
	priority: Mapped[str] = mapped_column(String(16), nullable=False, default="normal")
	instruction: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	due_at: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
	seen_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	completion_note: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class OaParaph(Base):
	__tablename__ = "oa_paraphs"
	__table_args__ = (
		Index("ix_oa_paraphs_letter_id", "letter_id"),
		Index("ix_oa_paraphs_position_id", "position_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	letter_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_letters.id", ondelete="CASCADE"), nullable=False
	)
	referral_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_referrals.id", ondelete="SET NULL"), nullable=True
	)
	position_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_positions.id", ondelete="RESTRICT"), nullable=False
	)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
	text: Mapped[str] = mapped_column(Text, nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class OaLetterAttachment(Base):
	__tablename__ = "oa_letter_attachments"
	__table_args__ = (Index("ix_oa_letter_attachments_letter_id", "letter_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	letter_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_letters.id", ondelete="CASCADE"), nullable=False
	)
	file_storage_id: Mapped[str] = mapped_column(
		String(36), ForeignKey("file_storage.id", ondelete="RESTRICT"), nullable=False
	)
	title: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	ocr_text: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	uploaded_by_user_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
	)
	uploaded_as_position_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_positions.id", ondelete="RESTRICT"), nullable=False
	)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class OaLetterLink(Base):
	__tablename__ = "oa_letter_links"
	__table_args__ = (
		UniqueConstraint("letter_id", "related_letter_id", "link_kind", name="uq_oa_letter_links"),
		Index("ix_oa_letter_links_letter_id", "letter_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	letter_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_letters.id", ondelete="CASCADE"), nullable=False
	)
	related_letter_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_letters.id", ondelete="CASCADE"), nullable=False
	)
	link_kind: Mapped[str] = mapped_column(String(16), nullable=False, default="related")
	created_by_user_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
	)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class OaAuditLog(Base):
	__tablename__ = "oa_audit_logs"
	__table_args__ = (
		Index("ix_oa_audit_logs_business_id", "business_id"),
		Index("ix_oa_audit_logs_letter_id", "letter_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	letter_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_letters.id", ondelete="SET NULL"), nullable=True
	)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
	position_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_positions.id", ondelete="SET NULL"), nullable=True
	)
	action: Mapped[str] = mapped_column(String(64), nullable=False)
	payload: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class OaSecretariat(Base):
	__tablename__ = "oa_secretariats"
	__table_args__ = (
		UniqueConstraint("business_id", "code", name="uq_oa_secretariats_biz_code"),
		Index("ix_oa_secretariats_business_id", "business_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	org_unit_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_org_units.id", ondelete="SET NULL"), nullable=True
	)
	branch_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name_i18n: Mapped[dict] = mapped_column(JSON, nullable=False)
	incoming_prefix: Mapped[str] = mapped_column(String(16), nullable=False, default="IN")
	outgoing_prefix: Mapped[str] = mapped_column(String(16), nullable=False, default="OUT")
	internal_prefix: Mapped[str] = mapped_column(String(16), nullable=False, default="INT")
	is_confidential: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	is_default: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	ece_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	ece_email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class OaExternalOrg(Base):
	__tablename__ = "oa_external_orgs"
	__table_args__ = (
		UniqueConstraint("business_id", "code", name="uq_oa_external_orgs_biz_code"),
		Index("ix_oa_external_orgs_business_id", "business_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name_i18n: Mapped[dict] = mapped_column(JSON, nullable=False)
	ece_email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	national_id: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
	phone: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
	address: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	extra_info: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class OaUserSignature(Base):
	__tablename__ = "oa_user_signatures"
	__table_args__ = (Index("ix_oa_user_signatures_business_user", "business_id", "user_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
	title: Mapped[str] = mapped_column(String(120), nullable=False, default="default")
	image_file_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
	color: Mapped[Optional[str]] = mapped_column(String(16), nullable=True)
	is_default: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class OaSignPathTemplate(Base):
	__tablename__ = "oa_sign_path_templates"
	__table_args__ = (Index("ix_oa_sign_path_templates_business_id", "business_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	name: Mapped[str] = mapped_column(String(120), nullable=False)
	letter_kind: Mapped[Optional[str]] = mapped_column(String(16), nullable=True)
	require_before_register: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class OaSignPathTemplateStep(Base):
	__tablename__ = "oa_sign_path_template_steps"
	__table_args__ = (Index("ix_oa_sign_path_tpl_steps_template_id", "template_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	template_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_sign_path_templates.id", ondelete="CASCADE"), nullable=False
	)
	position_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_positions.id", ondelete="RESTRICT"), nullable=False
	)
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	is_required: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	role_title: Mapped[Optional[str]] = mapped_column(String(120), nullable=True)


class OaLetterSignStep(Base):
	__tablename__ = "oa_letter_sign_steps"
	__table_args__ = (Index("ix_oa_letter_sign_steps_letter_id", "letter_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	letter_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_letters.id", ondelete="CASCADE"), nullable=False
	)
	position_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_positions.id", ondelete="RESTRICT"), nullable=False
	)
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	is_required: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
	signed_by_user_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	signature_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_user_signatures.id", ondelete="SET NULL"), nullable=True
	)
	image_file_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
	note: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	signed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class OaLetterVersion(Base):
	__tablename__ = "oa_letter_versions"
	__table_args__ = (Index("ix_oa_letter_versions_letter_id", "letter_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	letter_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_letters.id", ondelete="CASCADE"), nullable=False
	)
	version_no: Mapped[int] = mapped_column(Integer, nullable=False)
	subject: Mapped[str] = mapped_column(String(500), nullable=False)
	body: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	body_format: Mapped[str] = mapped_column(String(16), nullable=False, default="markdown")
	created_by_user_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
	)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class OaDispatch(Base):
	__tablename__ = "oa_dispatches"
	__table_args__ = (Index("ix_oa_dispatches_letter_id", "letter_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	letter_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_letters.id", ondelete="CASCADE"), nullable=False
	)
	from_position_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_positions.id", ondelete="RESTRICT"), nullable=False
	)
	to_position_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("oa_positions.id", ondelete="RESTRICT"), nullable=False
	)
	from_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
	instruction: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="dispatched")
	acknowledged_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	acknowledged_by_user_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class OaEceMessage(Base):
	__tablename__ = "oa_ece_messages"
	__table_args__ = (Index("ix_oa_ece_messages_business_id", "business_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	letter_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_letters.id", ondelete="SET NULL"), nullable=True
	)
	secretariat_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_secretariats.id", ondelete="SET NULL"), nullable=True
	)
	external_org_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_external_orgs.id", ondelete="SET NULL"), nullable=True
	)
	direction: Mapped[str] = mapped_column(String(8), nullable=False)
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="draft")
	to_email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	from_email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	xml_content: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	receipt_number: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
	error_message: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	created_by_user_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	sent_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class OaCartableRule(Base):
	__tablename__ = "oa_cartable_rules"
	__table_args__ = (Index("ix_oa_cartable_rules_business_id", "business_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	position_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_positions.id", ondelete="CASCADE"), nullable=True
	)
	name: Mapped[str] = mapped_column(String(120), nullable=False)
	priority: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	conditions: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
	actions: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class OaCartableSavedFilter(Base):
	__tablename__ = "oa_cartable_saved_filters"
	__table_args__ = (
		UniqueConstraint("business_id", "user_id", "name", name="uq_oa_cartable_saved_filters_name"),
		Index("ix_oa_cartable_saved_filters_business_user", "business_id", "user_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	user_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
	)
	name: Mapped[str] = mapped_column(String(80), nullable=False)
	folder: Mapped[str] = mapped_column(String(32), nullable=False, default="inbox")
	query_text: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
	date_from: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
	date_to: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class OaArchiveFolder(Base):
	__tablename__ = "oa_archive_folders"
	__table_args__ = (
		UniqueConstraint("business_id", "code", name="uq_oa_archive_folders_biz_code"),
		Index("ix_oa_archive_folders_business_id", "business_id"),
		Index("ix_oa_archive_folders_parent_id", "parent_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	parent_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_archive_folders.id", ondelete="SET NULL"), nullable=True
	)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	name_i18n: Mapped[dict] = mapped_column(JSON, nullable=False)
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class OaMailboxMessage(Base):
	__tablename__ = "oa_mailbox_messages"
	__table_args__ = (Index("ix_oa_mailbox_messages_business_id", "business_id"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	letter_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("oa_letters.id", ondelete="SET NULL"), nullable=True
	)
	direction: Mapped[str] = mapped_column(String(8), nullable=False)
	from_email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	to_email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	subject: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
	body: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="imported")
	message_id: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
