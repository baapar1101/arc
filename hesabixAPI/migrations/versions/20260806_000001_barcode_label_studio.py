"""Barcode label studio tables + marketplace plugin seed sync.

Revision ID: 20260806_000001_barcode_label_studio
Revises: 20260803_000002_telephony_phase2_ops_tables
Create Date: 2026-08-06
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260806_000001_barcode_label_studio"
down_revision = "20260803_000002_telephony_phase2_ops_tables"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"label_templates",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("name", sa.String(length=160), nullable=False),
		sa.Column("description", sa.String(length=512), nullable=True),
		sa.Column("status", sa.String(length=16), nullable=False, server_default="draft"),
		sa.Column("is_default", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
		sa.Column("schema_version", sa.Integer(), nullable=False, server_default="1"),
		sa.Column("design_json", sa.JSON(), nullable=False),
		sa.Column("sheet_json", sa.JSON(), nullable=True),
		sa.Column("created_by", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.Column("published_at", sa.DateTime(), nullable=True),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["created_by"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_label_templates_business_id", "label_templates", ["business_id"])
	op.create_index("ix_label_templates_status", "label_templates", ["status"])
	op.create_index("ix_label_templates_is_default", "label_templates", ["is_default"])
	op.create_index(
		"ix_label_templates_business_status",
		"label_templates",
		["business_id", "status"],
	)

	op.create_table(
		"label_template_revisions",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("template_id", sa.Integer(), nullable=False),
		sa.Column("version_no", sa.Integer(), nullable=False),
		sa.Column("design_json", sa.JSON(), nullable=False),
		sa.Column("sheet_json", sa.JSON(), nullable=True),
		sa.Column("changelog", sa.String(length=512), nullable=True),
		sa.Column("created_by", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["template_id"], ["label_templates.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["created_by"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index(
		"ix_label_template_revisions_template_id",
		"label_template_revisions",
		["template_id"],
	)
	op.create_index(
		"ix_label_template_revisions_template_version",
		"label_template_revisions",
		["template_id", "version_no"],
		unique=True,
	)

	# Seed / sync marketplace plugin row (idempotent helper).
	bind = op.get_bind()
	from sqlalchemy.orm import sessionmaker

	from adapters.db.seed_data.marketplace_plugins_seed import ensure_default_marketplace_plugins

	Session = sessionmaker(bind=bind)
	session = Session()
	try:
		ensure_default_marketplace_plugins(session)
		session.commit()
	except Exception:
		session.rollback()
		raise
	finally:
		session.close()


def downgrade() -> None:
	op.drop_table("label_template_revisions")
	op.drop_table("label_templates")
