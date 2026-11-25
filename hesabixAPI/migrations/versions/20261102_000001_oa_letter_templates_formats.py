"""قالب نامه، فرمت کاغذ، سربرگ و فیلدهای غنی‌شده نامه.

Revision ID: 20261102_000001_oa_letter_templates_formats
Revises: 20261101_000005_office_automation_plugin
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261102_000001_oa_letter_templates_formats"
down_revision = "20261101_000005_office_automation_plugin"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column("oa_settings", sa.Column("background_file_id", sa.String(length=36), nullable=True))
	op.add_column("oa_settings", sa.Column("footer_text", sa.Text(), nullable=True))
	op.add_column("oa_settings", sa.Column("paper_size", sa.String(length=16), nullable=False, server_default=sa.text("'a4'")))
	op.add_column("oa_settings", sa.Column("paper_orientation", sa.String(length=16), nullable=False, server_default=sa.text("'portrait'")))
	op.add_column("oa_settings", sa.Column("margin_top", sa.Integer(), nullable=False, server_default=sa.text("20")))
	op.add_column("oa_settings", sa.Column("margin_right", sa.Integer(), nullable=False, server_default=sa.text("20")))
	op.add_column("oa_settings", sa.Column("margin_bottom", sa.Integer(), nullable=False, server_default=sa.text("20")))
	op.add_column("oa_settings", sa.Column("margin_left", sa.Integer(), nullable=False, server_default=sa.text("20")))
	op.add_column("oa_settings", sa.Column("default_body_format", sa.String(length=16), nullable=False, server_default=sa.text("'markdown'")))
	op.add_column("oa_settings", sa.Column("default_format_id", sa.Integer(), nullable=True))

	op.create_table(
		"oa_letter_formats",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("name", sa.String(length=120), nullable=False),
		sa.Column("paper_size", sa.String(length=16), nullable=False, server_default=sa.text("'a4'")),
		sa.Column("paper_orientation", sa.String(length=16), nullable=False, server_default=sa.text("'portrait'")),
		sa.Column("margin_top", sa.Integer(), nullable=False, server_default=sa.text("20")),
		sa.Column("margin_right", sa.Integer(), nullable=False, server_default=sa.text("20")),
		sa.Column("margin_bottom", sa.Integer(), nullable=False, server_default=sa.text("20")),
		sa.Column("margin_left", sa.Integer(), nullable=False, server_default=sa.text("20")),
		sa.Column("letterhead_file_id", sa.String(length=36), nullable=True),
		sa.Column("background_file_id", sa.String(length=36), nullable=True),
		sa.Column("footer_text", sa.Text(), nullable=True),
		sa.Column("header_html", sa.Text(), nullable=True),
		sa.Column("is_default", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_letter_formats_business_id", "oa_letter_formats", ["business_id"])

	op.create_table(
		"oa_letter_templates",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("name", sa.String(length=120), nullable=False),
		sa.Column("letter_kind", sa.String(length=16), nullable=True),
		sa.Column("subject", sa.String(length=500), nullable=True),
		sa.Column("body", sa.Text(), nullable=True),
		sa.Column("body_format", sa.String(length=16), nullable=False, server_default=sa.text("'markdown'")),
		sa.Column("format_id", sa.Integer(), nullable=True),
		sa.Column("is_default", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["format_id"], ["oa_letter_formats.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_letter_templates_business_id", "oa_letter_templates", ["business_id"])

	op.add_column("oa_letters", sa.Column("body_format", sa.String(length=16), nullable=False, server_default=sa.text("'markdown'")))
	op.add_column("oa_letters", sa.Column("sender_position_id", sa.Integer(), nullable=True))
	op.add_column("oa_letters", sa.Column("receiver_position_id", sa.Integer(), nullable=True))
	op.add_column("oa_letters", sa.Column("format_id", sa.Integer(), nullable=True))
	op.add_column("oa_letters", sa.Column("template_id", sa.Integer(), nullable=True))
	op.create_foreign_key("fk_oa_letters_sender_position_id", "oa_letters", "oa_positions", ["sender_position_id"], ["id"], ondelete="SET NULL")
	op.create_foreign_key("fk_oa_letters_receiver_position_id", "oa_letters", "oa_positions", ["receiver_position_id"], ["id"], ondelete="SET NULL")
	op.create_foreign_key("fk_oa_letters_format_id", "oa_letters", "oa_letter_formats", ["format_id"], ["id"], ondelete="SET NULL")
	op.create_foreign_key("fk_oa_letters_template_id", "oa_letters", "oa_letter_templates", ["template_id"], ["id"], ondelete="SET NULL")
	op.create_foreign_key("fk_oa_settings_default_format_id", "oa_settings", "oa_letter_formats", ["default_format_id"], ["id"], ondelete="SET NULL")


def downgrade() -> None:
	op.drop_constraint("fk_oa_settings_default_format_id", "oa_settings", type_="foreignkey")
	op.drop_constraint("fk_oa_letters_template_id", "oa_letters", type_="foreignkey")
	op.drop_constraint("fk_oa_letters_format_id", "oa_letters", type_="foreignkey")
	op.drop_constraint("fk_oa_letters_receiver_position_id", "oa_letters", type_="foreignkey")
	op.drop_constraint("fk_oa_letters_sender_position_id", "oa_letters", type_="foreignkey")
	op.drop_column("oa_letters", "template_id")
	op.drop_column("oa_letters", "format_id")
	op.drop_column("oa_letters", "receiver_position_id")
	op.drop_column("oa_letters", "sender_position_id")
	op.drop_column("oa_letters", "body_format")
	op.drop_index("ix_oa_letter_templates_business_id", table_name="oa_letter_templates")
	op.drop_table("oa_letter_templates")
	op.drop_index("ix_oa_letter_formats_business_id", table_name="oa_letter_formats")
	op.drop_table("oa_letter_formats")
	op.drop_column("oa_settings", "default_format_id")
	op.drop_column("oa_settings", "default_body_format")
	op.drop_column("oa_settings", "margin_left")
	op.drop_column("oa_settings", "margin_bottom")
	op.drop_column("oa_settings", "margin_right")
	op.drop_column("oa_settings", "margin_top")
	op.drop_column("oa_settings", "paper_orientation")
	op.drop_column("oa_settings", "paper_size")
	op.drop_column("oa_settings", "footer_text")
	op.drop_column("oa_settings", "background_file_id")
