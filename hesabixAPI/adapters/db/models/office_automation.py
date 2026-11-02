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
			"letter_kind",
			"secretariat_year",
			"secretariat_seq",
			unique=True,
			postgresql_where=text("secretariat_seq IS NOT NULL"),
			sqlite_where=text("secretariat_seq IS NOT NULL"),
		),
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
	extra_info: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class OaLetterNumberCounter(Base):
	__tablename__ = "oa_letter_number_counters"
	__table_args__ = (
		UniqueConstraint("business_id", "letter_kind", "year", name="uq_oa_letter_counters"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	letter_kind: Mapped[str] = mapped_column(String(16), nullable=False)
	year: Mapped[int] = mapped_column(Integer, nullable=False)
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
