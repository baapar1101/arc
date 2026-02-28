"""add code column to crm_leads, crm_deals, crm_activities

Revision ID: 20250228_000001
Revises: 20250227_000001_add_crm_tables
Create Date: 2025-02-28

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20250228_000001_add_crm_code_columns"
down_revision = "20250227_000001_add_crm_tables"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add code column to crm_leads (nullable initially for backfill)
    op.add_column("crm_leads", sa.Column("code", sa.String(50), nullable=True))
    conn = op.get_bind()
    # Backfill: L-{id} for existing leads
    conn.execute(sa.text(
        "UPDATE crm_leads SET code = 'L-' || id WHERE code IS NULL"
    ))
    op.alter_column("crm_leads", "code", nullable=False)
    op.create_unique_constraint(
        "uq_crm_leads_business_code", "crm_leads", ["business_id", "code"]
    )
    op.create_index("ix_crm_leads_code", "crm_leads", ["code"])

    # Add code column to crm_deals
    op.add_column("crm_deals", sa.Column("code", sa.String(50), nullable=True))
    conn.execute(sa.text(
        "UPDATE crm_deals SET code = 'D-' || id WHERE code IS NULL"
    ))
    op.alter_column("crm_deals", "code", nullable=False)
    op.create_unique_constraint(
        "uq_crm_deals_business_code", "crm_deals", ["business_id", "code"]
    )
    op.create_index("ix_crm_deals_code", "crm_deals", ["code"])

    # Add code column to crm_activities
    op.add_column("crm_activities", sa.Column("code", sa.String(50), nullable=True))
    conn.execute(sa.text(
        "UPDATE crm_activities SET code = 'A-' || id WHERE code IS NULL"
    ))
    op.alter_column("crm_activities", "code", nullable=False)
    op.create_unique_constraint(
        "uq_crm_activities_business_code", "crm_activities", ["business_id", "code"]
    )
    op.create_index("ix_crm_activities_code", "crm_activities", ["code"])


def downgrade() -> None:
    op.drop_index("ix_crm_activities_code", "crm_activities")
    op.drop_constraint("uq_crm_activities_business_code", "crm_activities", type_="unique")
    op.drop_column("crm_activities", "code")

    op.drop_index("ix_crm_deals_code", "crm_deals")
    op.drop_constraint("uq_crm_deals_business_code", "crm_deals", type_="unique")
    op.drop_column("crm_deals", "code")

    op.drop_index("ix_crm_leads_code", "crm_leads")
    op.drop_constraint("uq_crm_leads_business_code", "crm_leads", type_="unique")
    op.drop_column("crm_leads", "code")
