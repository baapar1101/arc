"""اتوماسیون اداری تجاری: دبیرخانه، ECE، امضا، ابلاغ، بایگانی، رهگیری.

Revision ID: 20261102_000003_oa_commercial_upgrade
Revises: 20261102_000002_pay_page_receipts_abuse
"""
from __future__ import annotations

import json
import secrets

import sqlalchemy as sa
from alembic import op

from adapters.db.seed_data.notification_event_types_seed import (
	NOTIFICATION_EVENT_TYPES_ROWS,
	OFFICE_AUTOMATION_EVENT_CODES,
)

revision = "20261102_000003_oa_commercial_upgrade"
down_revision = "20261102_000002_pay_page_receipts_abuse"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"oa_secretariats",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("org_unit_id", sa.Integer(), nullable=True),
		sa.Column("code", sa.String(length=64), nullable=False),
		sa.Column("name_i18n", sa.JSON(), nullable=False),
		sa.Column("incoming_prefix", sa.String(length=16), nullable=False, server_default=sa.text("'IN'")),
		sa.Column("outgoing_prefix", sa.String(length=16), nullable=False, server_default=sa.text("'OUT'")),
		sa.Column("internal_prefix", sa.String(length=16), nullable=False, server_default=sa.text("'INT'")),
		sa.Column("is_confidential", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("is_default", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("ece_enabled", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("ece_email", sa.String(length=255), nullable=True),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["org_unit_id"], ["oa_org_units.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_oa_secretariats_biz_code"),
	)
	op.create_index("ix_oa_secretariats_business_id", "oa_secretariats", ["business_id"])

	op.create_table(
		"oa_external_orgs",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("code", sa.String(length=64), nullable=False),
		sa.Column("name_i18n", sa.JSON(), nullable=False),
		sa.Column("ece_email", sa.String(length=255), nullable=True),
		sa.Column("national_id", sa.String(length=32), nullable=True),
		sa.Column("phone", sa.String(length=64), nullable=True),
		sa.Column("address", sa.Text(), nullable=True),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("extra_info", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_oa_external_orgs_biz_code"),
	)
	op.create_index("ix_oa_external_orgs_business_id", "oa_external_orgs", ["business_id"])

	op.create_table(
		"oa_archive_folders",
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
		sa.ForeignKeyConstraint(["parent_id"], ["oa_archive_folders.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_oa_archive_folders_biz_code"),
	)
	op.create_index("ix_oa_archive_folders_business_id", "oa_archive_folders", ["business_id"])
	op.create_index("ix_oa_archive_folders_parent_id", "oa_archive_folders", ["parent_id"])

	op.create_table(
		"oa_user_signatures",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("title", sa.String(length=120), nullable=False, server_default=sa.text("'default'")),
		sa.Column("image_file_id", sa.String(length=36), nullable=True),
		sa.Column("color", sa.String(length=16), nullable=True),
		sa.Column("is_default", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_user_signatures_business_user", "oa_user_signatures", ["business_id", "user_id"])

	op.create_table(
		"oa_sign_path_templates",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("name", sa.String(length=120), nullable=False),
		sa.Column("letter_kind", sa.String(length=16), nullable=True),
		sa.Column("require_before_register", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_sign_path_templates_business_id", "oa_sign_path_templates", ["business_id"])

	op.create_table(
		"oa_sign_path_template_steps",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("template_id", sa.Integer(), nullable=False),
		sa.Column("position_id", sa.Integer(), nullable=False),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
		sa.Column("is_required", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("role_title", sa.String(length=120), nullable=True),
		sa.ForeignKeyConstraint(["template_id"], ["oa_sign_path_templates.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["position_id"], ["oa_positions.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_sign_path_tpl_steps_template_id", "oa_sign_path_template_steps", ["template_id"])

	op.add_column("oa_positions", sa.Column("secretariat_id", sa.Integer(), nullable=True))
	op.create_index("ix_oa_positions_secretariat_id", "oa_positions", ["secretariat_id"])
	op.create_foreign_key(
		"fk_oa_positions_secretariat_id",
		"oa_positions",
		"oa_secretariats",
		["secretariat_id"],
		["id"],
		ondelete="SET NULL",
	)

	op.add_column("oa_letters", sa.Column("secretariat_id", sa.Integer(), nullable=True))
	op.add_column("oa_letters", sa.Column("external_org_id", sa.Integer(), nullable=True))
	op.add_column("oa_letters", sa.Column("archive_folder_id", sa.Integer(), nullable=True))
	op.add_column("oa_letters", sa.Column("tracking_token", sa.String(length=48), nullable=True))
	op.add_column("oa_letters", sa.Column("receipt_number", sa.String(length=64), nullable=True))
	op.add_column("oa_letters", sa.Column("receipt_date", sa.Date(), nullable=True))
	op.add_column("oa_letters", sa.Column("sign_status", sa.String(length=16), nullable=False, server_default=sa.text("'none'")))
	op.add_column("oa_letters", sa.Column("keywords", sa.String(length=500), nullable=True))
	op.add_column("oa_letters", sa.Column("search_text", sa.Text(), nullable=True))
	op.add_column("oa_letters", sa.Column("ocr_text", sa.Text(), nullable=True))
	op.add_column("oa_letters", sa.Column("ai_summary", sa.Text(), nullable=True))
	op.create_foreign_key("fk_oa_letters_secretariat_id", "oa_letters", "oa_secretariats", ["secretariat_id"], ["id"], ondelete="SET NULL")
	op.create_foreign_key("fk_oa_letters_external_org_id", "oa_letters", "oa_external_orgs", ["external_org_id"], ["id"], ondelete="SET NULL")
	op.create_foreign_key("fk_oa_letters_archive_folder_id", "oa_letters", "oa_archive_folders", ["archive_folder_id"], ["id"], ondelete="SET NULL")
	op.create_index("ix_oa_letters_secretariat_id", "oa_letters", ["secretariat_id"])
	op.create_index("ix_oa_letters_archive_folder_id", "oa_letters", ["archive_folder_id"])
	op.create_index("ix_oa_letters_tracking_token", "oa_letters", ["tracking_token"], unique=True)

	op.drop_index("uq_oa_letters_number", table_name="oa_letters")
	op.create_index(
		"uq_oa_letters_number",
		"oa_letters",
		["business_id", "secretariat_id", "letter_kind", "secretariat_year", "secretariat_seq"],
		unique=True,
		postgresql_where=sa.text("secretariat_seq IS NOT NULL"),
		sqlite_where=sa.text("secretariat_seq IS NOT NULL"),
	)

	op.add_column(
		"oa_letter_number_counters",
		sa.Column("secretariat_id", sa.Integer(), nullable=False, server_default=sa.text("0")),
	)
	op.drop_constraint("uq_oa_letter_counters", "oa_letter_number_counters", type_="unique")
	op.create_unique_constraint(
		"uq_oa_letter_counters",
		"oa_letter_number_counters",
		["business_id", "letter_kind", "year", "secretariat_id"],
	)

	op.add_column("oa_letter_attachments", sa.Column("ocr_text", sa.Text(), nullable=True))

	op.create_table(
		"oa_letter_sign_steps",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("letter_id", sa.Integer(), nullable=False),
		sa.Column("position_id", sa.Integer(), nullable=False),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
		sa.Column("is_required", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("status", sa.String(length=16), nullable=False, server_default=sa.text("'pending'")),
		sa.Column("signed_by_user_id", sa.Integer(), nullable=True),
		sa.Column("signature_id", sa.Integer(), nullable=True),
		sa.Column("image_file_id", sa.String(length=36), nullable=True),
		sa.Column("note", sa.Text(), nullable=True),
		sa.Column("signed_at", sa.DateTime(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["letter_id"], ["oa_letters.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["position_id"], ["oa_positions.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["signed_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["signature_id"], ["oa_user_signatures.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_letter_sign_steps_letter_id", "oa_letter_sign_steps", ["letter_id"])

	op.create_table(
		"oa_letter_versions",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("letter_id", sa.Integer(), nullable=False),
		sa.Column("version_no", sa.Integer(), nullable=False),
		sa.Column("subject", sa.String(length=500), nullable=False),
		sa.Column("body", sa.Text(), nullable=True),
		sa.Column("body_format", sa.String(length=16), nullable=False, server_default=sa.text("'markdown'")),
		sa.Column("created_by_user_id", sa.Integer(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["letter_id"], ["oa_letters.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_letter_versions_letter_id", "oa_letter_versions", ["letter_id"])

	op.create_table(
		"oa_dispatches",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("letter_id", sa.Integer(), nullable=False),
		sa.Column("from_position_id", sa.Integer(), nullable=False),
		sa.Column("to_position_id", sa.Integer(), nullable=False),
		sa.Column("from_user_id", sa.Integer(), nullable=False),
		sa.Column("instruction", sa.Text(), nullable=True),
		sa.Column("status", sa.String(length=16), nullable=False, server_default=sa.text("'dispatched'")),
		sa.Column("acknowledged_at", sa.DateTime(), nullable=True),
		sa.Column("acknowledged_by_user_id", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["letter_id"], ["oa_letters.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["from_position_id"], ["oa_positions.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["to_position_id"], ["oa_positions.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["from_user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["acknowledged_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_dispatches_letter_id", "oa_dispatches", ["letter_id"])

	op.create_table(
		"oa_ece_messages",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("letter_id", sa.Integer(), nullable=True),
		sa.Column("secretariat_id", sa.Integer(), nullable=True),
		sa.Column("external_org_id", sa.Integer(), nullable=True),
		sa.Column("direction", sa.String(length=8), nullable=False),
		sa.Column("status", sa.String(length=16), nullable=False, server_default=sa.text("'draft'")),
		sa.Column("to_email", sa.String(length=255), nullable=True),
		sa.Column("from_email", sa.String(length=255), nullable=True),
		sa.Column("xml_content", sa.Text(), nullable=True),
		sa.Column("receipt_number", sa.String(length=64), nullable=True),
		sa.Column("error_message", sa.Text(), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), nullable=True),
		sa.Column("sent_at", sa.DateTime(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["letter_id"], ["oa_letters.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["secretariat_id"], ["oa_secretariats.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["external_org_id"], ["oa_external_orgs.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_ece_messages_business_id", "oa_ece_messages", ["business_id"])

	op.create_table(
		"oa_cartable_rules",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("position_id", sa.Integer(), nullable=True),
		sa.Column("name", sa.String(length=120), nullable=False),
		sa.Column("priority", sa.Integer(), nullable=False, server_default=sa.text("0")),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("conditions", sa.JSON(), nullable=False),
		sa.Column("actions", sa.JSON(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["position_id"], ["oa_positions.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_cartable_rules_business_id", "oa_cartable_rules", ["business_id"])

	op.create_table(
		"oa_mailbox_messages",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("letter_id", sa.Integer(), nullable=True),
		sa.Column("direction", sa.String(length=8), nullable=False),
		sa.Column("from_email", sa.String(length=255), nullable=True),
		sa.Column("to_email", sa.String(length=255), nullable=True),
		sa.Column("subject", sa.String(length=500), nullable=True),
		sa.Column("body", sa.Text(), nullable=True),
		sa.Column("status", sa.String(length=16), nullable=False, server_default=sa.text("'imported'")),
		sa.Column("message_id", sa.String(length=255), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["letter_id"], ["oa_letters.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_mailbox_messages_business_id", "oa_mailbox_messages", ["business_id"])

	conn = op.get_bind()
	now = sa.func.now()
	settings_rows = conn.execute(
		sa.text("SELECT business_id, incoming_prefix, outgoing_prefix, internal_prefix FROM oa_settings")
	).fetchall()
	for row in settings_rows:
		conn.execute(
			sa.text(
				"""
				INSERT INTO oa_secretariats (
					business_id, code, name_i18n, incoming_prefix, outgoing_prefix, internal_prefix,
					is_default, is_active, created_at, updated_at
				) VALUES (
					:bid, 'main', CAST(:names AS JSON), :inp, :outp, :intp,
					true, true, NOW(), NOW()
				)
				"""
			),
			{
				"bid": row.business_id,
				"names": json.dumps({"fa": "دبیرخانه مرکزی", "en": "Central secretariat"}, ensure_ascii=False),
				"inp": row.incoming_prefix or "IN",
				"outp": row.outgoing_prefix or "OUT",
				"intp": row.internal_prefix or "INT",
			},
		)
	conn.execute(
		sa.text(
			"""
			UPDATE oa_letters l
			SET secretariat_id = s.id
			FROM oa_secretariats s
			WHERE l.business_id = s.business_id AND s.is_default = true AND l.secretariat_id IS NULL
			"""
		)
	)
	registered = conn.execute(
		sa.text("SELECT id FROM oa_letters WHERE secretariat_seq IS NOT NULL AND tracking_token IS NULL")
	).fetchall()
	for item in registered:
		conn.execute(
			sa.text("UPDATE oa_letters SET tracking_token = :tok WHERE id = :id"),
			{"tok": secrets.token_urlsafe(16)[:48], "id": item.id},
		)

	insp = sa.inspect(conn)
	if "notification_event_types" in insp.get_table_names():
		existing = {
			r[0]
			for r in conn.execute(sa.text("SELECT code FROM notification_event_types WHERE category = 'office_automation'")).fetchall()
		}
		rows = [r for r in NOTIFICATION_EVENT_TYPES_ROWS if r["code"] in OFFICE_AUTOMATION_EVENT_CODES and r["code"] not in existing]
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
	_ = now


def downgrade() -> None:
	op.drop_table("oa_mailbox_messages")
	op.drop_table("oa_cartable_rules")
	op.drop_table("oa_ece_messages")
	op.drop_table("oa_dispatches")
	op.drop_table("oa_letter_versions")
	op.drop_table("oa_letter_sign_steps")
	op.drop_column("oa_letter_attachments", "ocr_text")
	op.drop_constraint("uq_oa_letter_counters", "oa_letter_number_counters", type_="unique")
	op.drop_column("oa_letter_number_counters", "secretariat_id")
	op.create_unique_constraint(
		"uq_oa_letter_counters",
		"oa_letter_number_counters",
		["business_id", "letter_kind", "year"],
	)
	op.drop_index("uq_oa_letters_number", table_name="oa_letters")
	op.create_index(
		"uq_oa_letters_number",
		"oa_letters",
		["business_id", "letter_kind", "secretariat_year", "secretariat_seq"],
		unique=True,
		postgresql_where=sa.text("secretariat_seq IS NOT NULL"),
		sqlite_where=sa.text("secretariat_seq IS NOT NULL"),
	)
	op.drop_index("ix_oa_letters_tracking_token", table_name="oa_letters")
	op.drop_index("ix_oa_letters_archive_folder_id", table_name="oa_letters")
	op.drop_index("ix_oa_letters_secretariat_id", table_name="oa_letters")
	op.drop_constraint("fk_oa_letters_archive_folder_id", "oa_letters", type_="foreignkey")
	op.drop_constraint("fk_oa_letters_external_org_id", "oa_letters", type_="foreignkey")
	op.drop_constraint("fk_oa_letters_secretariat_id", "oa_letters", type_="foreignkey")
	for col in (
		"ai_summary",
		"ocr_text",
		"search_text",
		"keywords",
		"sign_status",
		"receipt_date",
		"receipt_number",
		"tracking_token",
		"archive_folder_id",
		"external_org_id",
		"secretariat_id",
	):
		op.drop_column("oa_letters", col)
	op.drop_constraint("fk_oa_positions_secretariat_id", "oa_positions", type_="foreignkey")
	op.drop_index("ix_oa_positions_secretariat_id", table_name="oa_positions")
	op.drop_column("oa_positions", "secretariat_id")
	op.drop_table("oa_sign_path_template_steps")
	op.drop_table("oa_sign_path_templates")
	op.drop_table("oa_user_signatures")
	op.drop_table("oa_archive_folders")
	op.drop_table("oa_external_orgs")
	op.drop_table("oa_secretariats")
