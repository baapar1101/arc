"""add crm tables (process definitions, stages, leads, deals, activities)

Revision ID: 20250227_000001
Revises: 20250226_000002_add_bale_messenger_support
Create Date: 2025-02-27

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20250227_000001_add_crm_tables"
down_revision = "20250226_000002_add_bale_messenger_support"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "crm_process_definitions",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("process_type", sa.String(50), nullable=False),
        sa.Column("code", sa.String(50), nullable=False),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("is_default", sa.Boolean(), nullable=False, server_default="0"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default="1"),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.Column("created_by_user_id", sa.Integer(), nullable=True),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("business_id", "process_type", "code", name="uq_crm_process_def_business_type_code"),
    )
    op.create_index("ix_crm_process_definitions_business_id", "crm_process_definitions", ["business_id"])
    op.create_index("ix_crm_process_definitions_process_type", "crm_process_definitions", ["process_type"])
    op.create_index("ix_crm_process_definitions_code", "crm_process_definitions", ["code"])
    op.create_index("idx_crm_process_def_business_type", "crm_process_definitions", ["business_id", "process_type"])

    op.create_table(
        "crm_process_stages",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("process_definition_id", sa.Integer(), nullable=False),
        sa.Column("stage_code", sa.String(50), nullable=False),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("order_index", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("color", sa.String(20), nullable=True),
        sa.Column("is_win", sa.Boolean(), nullable=False, server_default="0"),
        sa.Column("is_lost", sa.Boolean(), nullable=False, server_default="0"),
        sa.Column("allow_transition_to", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["process_definition_id"], ["crm_process_definitions.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("process_definition_id", "stage_code", name="uq_crm_process_stage_def_code"),
    )
    op.create_index("ix_crm_process_stages_process_definition_id", "crm_process_stages", ["process_definition_id"])
    op.create_index("ix_crm_process_stages_stage_code", "crm_process_stages", ["stage_code"])

    op.create_table(
        "crm_leads",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("process_definition_id", sa.Integer(), nullable=False),
        sa.Column("stage_id", sa.Integer(), nullable=False),
        sa.Column("source_code", sa.String(50), nullable=True),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("company_name", sa.String(255), nullable=True),
        sa.Column("mobile", sa.String(20), nullable=True),
        sa.Column("email", sa.String(255), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("assigned_to_user_id", sa.Integer(), nullable=True),
        sa.Column("person_id", sa.Integer(), nullable=True),
        sa.Column("converted_at", sa.DateTime(), nullable=True),
        sa.Column("extra_info", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.Column("created_by_user_id", sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["process_definition_id"], ["crm_process_definitions.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["stage_id"], ["crm_process_stages.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["assigned_to_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_crm_leads_business_id", "crm_leads", ["business_id"])
    op.create_index("ix_crm_leads_stage_id", "crm_leads", ["stage_id"])
    op.create_index("ix_crm_leads_mobile", "crm_leads", ["mobile"])
    op.create_index("ix_crm_leads_email", "crm_leads", ["email"])
    op.create_index("idx_crm_leads_business_stage", "crm_leads", ["business_id", "stage_id"])

    op.create_table(
        "crm_deals",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("person_id", sa.Integer(), nullable=False),
        sa.Column("process_definition_id", sa.Integer(), nullable=False),
        sa.Column("stage_id", sa.Integer(), nullable=False),
        sa.Column("title", sa.String(255), nullable=False),
        sa.Column("amount", sa.Numeric(18, 2), nullable=False, server_default="0"),
        sa.Column("currency_id", sa.Integer(), nullable=True),
        sa.Column("probability_percent", sa.Integer(), nullable=True),
        sa.Column("expected_close_date", sa.Date(), nullable=True),
        sa.Column("closed_at", sa.DateTime(), nullable=True),
        sa.Column("document_id", sa.Integer(), nullable=True),
        sa.Column("assigned_to_user_id", sa.Integer(), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("extra_info", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.Column("created_by_user_id", sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["process_definition_id"], ["crm_process_definitions.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["stage_id"], ["crm_process_stages.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["currency_id"], ["currencies.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["document_id"], ["documents.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["assigned_to_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_crm_deals_business_id", "crm_deals", ["business_id"])
    op.create_index("ix_crm_deals_person_id", "crm_deals", ["person_id"])
    op.create_index("ix_crm_deals_stage_id", "crm_deals", ["stage_id"])
    op.create_index("idx_crm_deals_business_stage", "crm_deals", ["business_id", "stage_id"])

    op.create_table(
        "crm_activities",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("person_id", sa.Integer(), nullable=False),
        sa.Column("activity_type", sa.String(50), nullable=False),
        sa.Column("subject", sa.String(255), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("activity_date", sa.DateTime(), nullable=False),
        sa.Column("deal_id", sa.Integer(), nullable=True),
        sa.Column("created_by_user_id", sa.Integer(), nullable=False),
        sa.Column("extra_info", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["deal_id"], ["crm_deals.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_crm_activities_business_id", "crm_activities", ["business_id"])
    op.create_index("ix_crm_activities_person_id", "crm_activities", ["person_id"])
    op.create_index("idx_crm_activities_person", "crm_activities", ["business_id", "person_id"])


def downgrade() -> None:
    op.drop_index("idx_crm_activities_person", "crm_activities")
    op.drop_index("ix_crm_activities_person_id", "crm_activities")
    op.drop_index("ix_crm_activities_business_id", "crm_activities")
    op.drop_table("crm_activities")

    op.drop_index("idx_crm_deals_business_stage", "crm_deals")
    op.drop_index("ix_crm_deals_stage_id", "crm_deals")
    op.drop_index("ix_crm_deals_person_id", "crm_deals")
    op.drop_index("ix_crm_deals_business_id", "crm_deals")
    op.drop_table("crm_deals")

    op.drop_index("idx_crm_leads_business_stage", "crm_leads")
    op.drop_index("ix_crm_leads_email", "crm_leads")
    op.drop_index("ix_crm_leads_mobile", "crm_leads")
    op.drop_index("ix_crm_leads_stage_id", "crm_leads")
    op.drop_index("ix_crm_leads_business_id", "crm_leads")
    op.drop_table("crm_leads")

    op.drop_index("ix_crm_process_stages_stage_code", "crm_process_stages")
    op.drop_index("ix_crm_process_stages_process_definition_id", "crm_process_stages")
    op.drop_table("crm_process_stages")

    op.drop_index("idx_crm_process_def_business_type", "crm_process_definitions")
    op.drop_index("ix_crm_process_definitions_code", "crm_process_definitions")
    op.drop_index("ix_crm_process_definitions_process_type", "crm_process_definitions")
    op.drop_index("ix_crm_process_definitions_business_id", "crm_process_definitions")
    op.drop_table("crm_process_definitions")
