"""Phase 2+ tables: DLQ + metrics

Revision ID: 20260803_000002_telephony_phase2_ops_tables
Revises: 20260803_000001_telephony_asterisk_issabel_plugin
Create Date: 2026-08-03
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260803_000002_telephony_phase2_ops_tables"
down_revision = "20260803_000001_telephony_asterisk_issabel_plugin"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"telephony_event_dead_letters",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("pbx_id", sa.Integer(), nullable=True),
		sa.Column("event_id", sa.String(length=64), nullable=True),
		sa.Column("payload", sa.JSON(), nullable=False),
		sa.Column("error_message", sa.Text(), nullable=False),
		sa.Column("resolved", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("resolved_at", sa.DateTime(), nullable=True),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["pbx_id"], ["telephony_pbx_connections.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_telephony_event_dead_letters_business_id", "telephony_event_dead_letters", ["business_id"])
	op.create_index("idx_telephony_dlq_business_created", "telephony_event_dead_letters", ["business_id", "created_at"])

	op.create_table(
		"telephony_metric_counters",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("metric_key", sa.String(length=80), nullable=False),
		sa.Column("value", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "metric_key", name="uq_telephony_metric_biz_key"),
	)
	op.create_index("ix_telephony_metric_counters_business_id", "telephony_metric_counters", ["business_id"])


def downgrade() -> None:
	op.drop_table("telephony_metric_counters")
	op.drop_table("telephony_event_dead_letters")
