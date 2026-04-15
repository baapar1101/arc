"""CRM: activity optional person + lead_id, follow-up composite indexes

Revision ID: 20260415_000002_crm_activity_lead_and_indexes
Revises: 20260415_000001_add_file_storage_shares
Create Date: 2026-04-15
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260415_000002_crm_activity_lead_and_indexes"
down_revision = "20260415_000001_add_file_storage_shares"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("crm_activities", sa.Column("lead_id", sa.Integer(), nullable=True))
    op.create_foreign_key(
        "fk_crm_activities_lead_id",
        "crm_activities",
        "crm_leads",
        ["lead_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index("idx_crm_activities_business_lead", "crm_activities", ["business_id", "lead_id"])
    op.alter_column("crm_activities", "person_id", existing_type=sa.Integer(), nullable=True)

    op.create_index("ix_crm_leads_business_next_followup", "crm_leads", ["business_id", "next_follow_up_at"])
    op.create_index("ix_crm_deals_business_next_followup", "crm_deals", ["business_id", "next_follow_up_at"])
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_crm_deals_open_followup "
        "ON crm_deals (business_id, next_follow_up_at) WHERE closed_at IS NULL"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_crm_deals_open_followup")
    op.drop_index("ix_crm_deals_business_next_followup", table_name="crm_deals")
    op.drop_index("ix_crm_leads_business_next_followup", table_name="crm_leads")

    op.alter_column("crm_activities", "person_id", existing_type=sa.Integer(), nullable=False)
    op.execute("DELETE FROM crm_activities WHERE person_id IS NULL")
    op.drop_index("idx_crm_activities_business_lead", table_name="crm_activities")
    op.drop_constraint("fk_crm_activities_lead_id", "crm_activities", type_="foreignkey")
    op.drop_column("crm_activities", "lead_id")
