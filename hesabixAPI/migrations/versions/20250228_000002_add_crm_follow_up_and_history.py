"""add next_follow_up_at to leads/deals and crm_change_history table

Revision ID: 20250228_000002
Revises: 20250228_000001_add_crm_code_columns
Create Date: 2025-02-28

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20250228_000002_add_crm_follow_up_and_history"
down_revision = "20250228_000001_add_crm_code_columns"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("crm_leads", sa.Column("next_follow_up_at", sa.DateTime(), nullable=True))
    op.add_column("crm_deals", sa.Column("next_follow_up_at", sa.DateTime(), nullable=True))
    op.create_index("ix_crm_leads_next_follow_up_at", "crm_leads", ["next_follow_up_at"])
    op.create_index("ix_crm_deals_next_follow_up_at", "crm_deals", ["next_follow_up_at"])

    op.create_table(
        "crm_change_history",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("entity_type", sa.String(20), nullable=False, comment="lead | deal"),
        sa.Column("entity_id", sa.Integer(), nullable=False),
        sa.Column("field_name", sa.String(80), nullable=False),
        sa.Column("old_value", sa.Text(), nullable=True),
        sa.Column("new_value", sa.Text(), nullable=True),
        sa.Column("changed_at", sa.DateTime(), nullable=False),
        sa.Column("changed_by_user_id", sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["changed_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("idx_crm_history_entity", "crm_change_history", ["business_id", "entity_type", "entity_id"])
    op.create_index("ix_crm_change_history_changed_at", "crm_change_history", ["changed_at"])


def downgrade() -> None:
    op.drop_index("ix_crm_change_history_changed_at", "crm_change_history")
    op.drop_index("idx_crm_history_entity", "crm_change_history")
    op.drop_table("crm_change_history")
    op.drop_index("ix_crm_deals_next_follow_up_at", "crm_deals")
    op.drop_index("ix_crm_leads_next_follow_up_at", "crm_leads")
    op.drop_column("crm_deals", "next_follow_up_at")
    op.drop_column("crm_leads", "next_follow_up_at")
