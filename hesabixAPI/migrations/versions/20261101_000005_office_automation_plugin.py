"""افزونه اتوماسیون اداری سمت‌محور: جداول نامه، کارتابل، سمت و تصدی.

Revision ID: 20261101_000005_office_automation_plugin
Revises: 20261101_000004_business_pay_pages
"""
from __future__ import annotations

import json

import sqlalchemy as sa
from alembic import op

from adapters.db.seed_data.notification_event_types_seed import (
	NOTIFICATION_EVENT_TYPES_ROWS,
	OFFICE_AUTOMATION_EVENT_CODES,
)

revision = "20261101_000005_office_automation_plugin"
down_revision = "20261101_000004_business_pay_pages"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"oa_settings",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("numbering_calendar", sa.String(length=16), nullable=False, server_default=sa.text("'jalali'")),
		sa.Column("incoming_prefix", sa.String(length=16), nullable=False, server_default=sa.text("'IN'")),
		sa.Column("outgoing_prefix", sa.String(length=16), nullable=False, server_default=sa.text("'OUT'")),
		sa.Column("internal_prefix", sa.String(length=16), nullable=False, server_default=sa.text("'INT'")),
		sa.Column("letterhead_file_id", sa.String(length=36), nullable=True),
		sa.Column("extra_settings", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", name="uq_oa_settings_business"),
	)
	op.create_index("ix_oa_settings_business_id", "oa_settings", ["business_id"])

	op.create_table(
		"oa_org_units",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("parent_id", sa.Integer(), nullable=True),
		sa.Column("code", sa.String(length=64), nullable=False),
		sa.Column("name_i18n", sa.JSON(), nullable=False),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["parent_id"], ["oa_org_units.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_oa_org_units_biz_code"),
	)
	op.create_index("ix_oa_org_units_business_id", "oa_org_units", ["business_id"])
	op.create_index("ix_oa_org_units_parent_id", "oa_org_units", ["parent_id"])

	op.create_table(
		"oa_positions",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("org_unit_id", sa.Integer(), nullable=False),
		sa.Column("code", sa.String(length=64), nullable=False),
		sa.Column("name_i18n", sa.JSON(), nullable=False),
		sa.Column("is_secretariat", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("can_view_subtree", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["org_unit_id"], ["oa_org_units.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_oa_positions_biz_code"),
	)
	op.create_index("ix_oa_positions_business_id", "oa_positions", ["business_id"])
	op.create_index("ix_oa_positions_org_unit_id", "oa_positions", ["org_unit_id"])

	op.create_table(
		"oa_position_holders",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("position_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("starts_at", sa.DateTime(), nullable=False),
		sa.Column("ends_at", sa.DateTime(), nullable=True),
		sa.Column("is_primary", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["position_id"], ["oa_positions.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_position_holders_business_id", "oa_position_holders", ["business_id"])
	op.create_index("ix_oa_position_holders_position_id", "oa_position_holders", ["position_id"])
	op.create_index("ix_oa_position_holders_user_id", "oa_position_holders", ["user_id"])

	op.create_table(
		"oa_delegations",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("position_id", sa.Integer(), nullable=False),
		sa.Column("delegate_user_id", sa.Integer(), nullable=False),
		sa.Column("created_by_user_id", sa.Integer(), nullable=False),
		sa.Column("scope", sa.String(length=16), nullable=False, server_default=sa.text("'full'")),
		sa.Column("starts_at", sa.DateTime(), nullable=False),
		sa.Column("ends_at", sa.DateTime(), nullable=True),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["position_id"], ["oa_positions.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["delegate_user_id"], ["users.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_delegations_business_id", "oa_delegations", ["business_id"])
	op.create_index("ix_oa_delegations_position_id", "oa_delegations", ["position_id"])
	op.create_index("ix_oa_delegations_delegate_user_id", "oa_delegations", ["delegate_user_id"])

	op.create_table(
		"oa_letters",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("letter_kind", sa.String(length=16), nullable=False, server_default=sa.text("'internal'")),
		sa.Column("status", sa.String(length=24), nullable=False, server_default=sa.text("'draft'")),
		sa.Column("subject", sa.String(length=500), nullable=False),
		sa.Column("body", sa.Text(), nullable=True),
		sa.Column("locale", sa.String(length=8), nullable=False, server_default=sa.text("'fa'")),
		sa.Column("letter_date", sa.Date(), nullable=False),
		sa.Column("urgency", sa.String(length=16), nullable=False, server_default=sa.text("'normal'")),
		sa.Column("confidentiality", sa.String(length=16), nullable=False, server_default=sa.text("'normal'")),
		sa.Column("sender_name", sa.String(length=255), nullable=True),
		sa.Column("sender_org", sa.String(length=255), nullable=True),
		sa.Column("receiver_name", sa.String(length=255), nullable=True),
		sa.Column("receiver_org", sa.String(length=255), nullable=True),
		sa.Column("origin_position_id", sa.Integer(), nullable=False),
		sa.Column("created_by_user_id", sa.Integer(), nullable=False),
		sa.Column("registered_at", sa.DateTime(), nullable=True),
		sa.Column("registered_by_user_id", sa.Integer(), nullable=True),
		sa.Column("registered_by_position_id", sa.Integer(), nullable=True),
		sa.Column("secretariat_number", sa.String(length=64), nullable=True),
		sa.Column("secretariat_year", sa.Integer(), nullable=True),
		sa.Column("secretariat_seq", sa.Integer(), nullable=True),
		sa.Column("follow_up_at", sa.Date(), nullable=True),
		sa.Column("person_id", sa.Integer(), nullable=True),
		sa.Column("extra_info", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["origin_position_id"], ["oa_positions.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["registered_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["registered_by_position_id"], ["oa_positions.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index(
		"uq_oa_letters_number",
		"oa_letters",
		["business_id", "letter_kind", "secretariat_year", "secretariat_seq"],
		unique=True,
		postgresql_where=sa.text("secretariat_seq IS NOT NULL"),
		sqlite_where=sa.text("secretariat_seq IS NOT NULL"),
	)
	op.create_index("ix_oa_letters_business_id", "oa_letters", ["business_id"])
	op.create_index("ix_oa_letters_status", "oa_letters", ["business_id", "status"])
	op.create_index("ix_oa_letters_kind", "oa_letters", ["business_id", "letter_kind"])
	op.create_index("ix_oa_letters_origin_position_id", "oa_letters", ["origin_position_id"])

	op.create_table(
		"oa_letter_number_counters",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("letter_kind", sa.String(length=16), nullable=False),
		sa.Column("year", sa.Integer(), nullable=False),
		sa.Column("last_seq", sa.Integer(), nullable=False, server_default=sa.text("0")),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "letter_kind", "year", name="uq_oa_letter_counters"),
	)

	op.create_table(
		"oa_referrals",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("letter_id", sa.Integer(), nullable=False),
		sa.Column("from_position_id", sa.Integer(), nullable=False),
		sa.Column("to_position_id", sa.Integer(), nullable=False),
		sa.Column("from_user_id", sa.Integer(), nullable=False),
		sa.Column("parent_referral_id", sa.Integer(), nullable=True),
		sa.Column("kind", sa.String(length=16), nullable=False, server_default=sa.text("'action'")),
		sa.Column("priority", sa.String(length=16), nullable=False, server_default=sa.text("'normal'")),
		sa.Column("instruction", sa.Text(), nullable=True),
		sa.Column("due_at", sa.Date(), nullable=True),
		sa.Column("status", sa.String(length=16), nullable=False, server_default=sa.text("'pending'")),
		sa.Column("seen_at", sa.DateTime(), nullable=True),
		sa.Column("completed_at", sa.DateTime(), nullable=True),
		sa.Column("completion_note", sa.Text(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["letter_id"], ["oa_letters.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["from_position_id"], ["oa_positions.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["to_position_id"], ["oa_positions.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["from_user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["parent_referral_id"], ["oa_referrals.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_referrals_letter_id", "oa_referrals", ["letter_id"])
	op.create_index("ix_oa_referrals_to_position_id", "oa_referrals", ["to_position_id", "status"])
	op.create_index("ix_oa_referrals_from_position_id", "oa_referrals", ["from_position_id"])
	op.create_index("ix_oa_referrals_business_id", "oa_referrals", ["business_id"])

	op.create_table(
		"oa_paraphs",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("letter_id", sa.Integer(), nullable=False),
		sa.Column("referral_id", sa.Integer(), nullable=True),
		sa.Column("position_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("text", sa.Text(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["letter_id"], ["oa_letters.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["referral_id"], ["oa_referrals.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["position_id"], ["oa_positions.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_paraphs_letter_id", "oa_paraphs", ["letter_id"])
	op.create_index("ix_oa_paraphs_position_id", "oa_paraphs", ["position_id"])

	op.create_table(
		"oa_letter_attachments",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("letter_id", sa.Integer(), nullable=False),
		sa.Column("file_storage_id", sa.String(length=36), nullable=False),
		sa.Column("title", sa.String(length=255), nullable=True),
		sa.Column("uploaded_by_user_id", sa.Integer(), nullable=False),
		sa.Column("uploaded_as_position_id", sa.Integer(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["letter_id"], ["oa_letters.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["file_storage_id"], ["file_storage.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["uploaded_by_user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["uploaded_as_position_id"], ["oa_positions.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_letter_attachments_letter_id", "oa_letter_attachments", ["letter_id"])

	op.create_table(
		"oa_letter_links",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("letter_id", sa.Integer(), nullable=False),
		sa.Column("related_letter_id", sa.Integer(), nullable=False),
		sa.Column("link_kind", sa.String(length=16), nullable=False, server_default=sa.text("'related'")),
		sa.Column("created_by_user_id", sa.Integer(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["letter_id"], ["oa_letters.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["related_letter_id"], ["oa_letters.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("letter_id", "related_letter_id", "link_kind", name="uq_oa_letter_links"),
	)
	op.create_index("ix_oa_letter_links_letter_id", "oa_letter_links", ["letter_id"])

	op.create_table(
		"oa_audit_logs",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("letter_id", sa.Integer(), nullable=True),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("position_id", sa.Integer(), nullable=True),
		sa.Column("action", sa.String(length=64), nullable=False),
		sa.Column("payload", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["letter_id"], ["oa_letters.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["position_id"], ["oa_positions.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_audit_logs_business_id", "oa_audit_logs", ["business_id"])
	op.create_index("ix_oa_audit_logs_letter_id", "oa_audit_logs", ["letter_id"])

	conn = op.get_bind()
	insp = sa.inspect(conn)
	if "notification_event_types" in insp.get_table_names():
		rows = [r for r in NOTIFICATION_EVENT_TYPES_ROWS if r["code"] in OFFICE_AUTOMATION_EVENT_CODES]
		for row in rows:
			conn.execute(
				sa.text(
					"""
					INSERT INTO notification_event_types (
						code, name, description, category, available_variables,
						default_sms_template, default_email_template, default_email_subject,
						is_active, requires_approval, created_at, updated_at
					) VALUES (
						:code, :name, :description, :category, CAST(:vars AS JSONB),
						:dst, :det, :des,
						true, false, NOW(), NOW()
					)
					ON CONFLICT (code) DO NOTHING
					"""
				),
				{
					"code": row["code"],
					"name": row["name"],
					"description": row.get("description"),
					"category": row.get("category"),
					"vars": json.dumps(row["available_variables"], ensure_ascii=False),
					"dst": row.get("default_sms_template"),
					"det": row.get("default_email_template"),
					"des": row.get("default_email_subject"),
				},
			)


def downgrade() -> None:
	conn = op.get_bind()
	insp = sa.inspect(conn)
	if "notification_event_types" in insp.get_table_names():
		for code in OFFICE_AUTOMATION_EVENT_CODES:
			conn.execute(
				sa.text("DELETE FROM notification_event_types WHERE code = :c"),
				{"c": code},
			)
	op.drop_table("oa_audit_logs")
	op.drop_table("oa_letter_links")
	op.drop_table("oa_letter_attachments")
	op.drop_table("oa_paraphs")
	op.drop_table("oa_referrals")
	op.drop_table("oa_letter_number_counters")
	op.drop_table("oa_letters")
	op.drop_table("oa_delegations")
	op.drop_table("oa_position_holders")
	op.drop_table("oa_positions")
	op.drop_table("oa_org_units")
	op.drop_table("oa_settings")
