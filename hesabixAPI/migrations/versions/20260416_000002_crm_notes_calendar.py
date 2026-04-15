"""CRM calendar notes, types, ACL, comments, audit

Revision ID: 20260416_000002_crm_notes_calendar
Revises: 20260416_000001_add_use_sftp_business_ftp_backup
Create Date: 2026-04-16
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260416_000002_crm_notes_calendar"
down_revision = "20260416_000001_add_use_sftp_business_ftp_backup"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "crm_note_types",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("code", sa.String(length=50), nullable=False),
        sa.Column("title_i18n", sa.JSON(), nullable=False),
        sa.Column(
            "scheduling_mode",
            sa.String(length=20),
            nullable=False,
            server_default="day_only",
            comment="day_only | meeting",
        ),
        sa.Column("allow_comments", sa.Boolean(), nullable=False, server_default="1"),
        sa.Column("is_system", sa.Boolean(), nullable=False, server_default="0"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default="1"),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("business_id", "code", name="uq_crm_note_types_business_code"),
    )
    op.create_index("ix_crm_note_types_business_id", "crm_note_types", ["business_id"])

    op.create_table(
        "crm_notes",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("note_type_id", sa.Integer(), nullable=False),
        sa.Column(
            "visibility",
            sa.String(length=20),
            nullable=False,
            comment="private | business_public | shared",
        ),
        sa.Column("title", sa.String(length=255), nullable=True),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("occurs_on", sa.Date(), nullable=False),
        sa.Column("starts_at", sa.DateTime(), nullable=True),
        sa.Column("ends_at", sa.DateTime(), nullable=True),
        sa.Column("lead_id", sa.Integer(), nullable=True),
        sa.Column("created_by_user_id", sa.Integer(), nullable=False),
        sa.Column(
            "status",
            sa.String(length=20),
            nullable=False,
            server_default="active",
            comment="active | archived | cancelled",
        ),
        sa.Column("deleted_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["lead_id"], ["crm_leads.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["note_type_id"], ["crm_note_types.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_crm_notes_business_occurs_on", "crm_notes", ["business_id", "occurs_on"])
    op.create_index("ix_crm_notes_business_deleted", "crm_notes", ["business_id", "deleted_at"])
    op.create_index("ix_crm_notes_lead_id", "crm_notes", ["lead_id"])

    op.create_table(
        "crm_note_acl_users",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("note_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["note_id"], ["crm_notes.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("note_id", "user_id", name="uq_crm_note_acl_note_user"),
    )
    op.create_index("ix_crm_note_acl_note_id", "crm_note_acl_users", ["note_id"])

    op.create_table(
        "crm_note_comments",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("note_id", sa.Integer(), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("created_by_user_id", sa.Integer(), nullable=False),
        sa.Column("deleted_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["note_id"], ["crm_notes.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_crm_note_comments_note_id", "crm_note_comments", ["note_id"])

    op.create_table(
        "crm_note_audit_events",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("note_id", sa.Integer(), nullable=False),
        sa.Column("actor_user_id", sa.Integer(), nullable=False),
        sa.Column("action", sa.String(length=50), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=True),
        sa.Column("occurred_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["actor_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["note_id"], ["crm_notes.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_crm_note_audit_note_id", "crm_note_audit_events", ["note_id"])


def downgrade() -> None:
    op.drop_index("ix_crm_note_audit_note_id", table_name="crm_note_audit_events")
    op.drop_table("crm_note_audit_events")
    op.drop_index("ix_crm_note_comments_note_id", table_name="crm_note_comments")
    op.drop_table("crm_note_comments")
    op.drop_index("ix_crm_note_acl_note_id", table_name="crm_note_acl_users")
    op.drop_table("crm_note_acl_users")
    op.drop_index("ix_crm_notes_lead_id", table_name="crm_notes")
    op.drop_index("ix_crm_notes_business_deleted", table_name="crm_notes")
    op.drop_index("ix_crm_notes_business_occurs_on", table_name="crm_notes")
    op.drop_table("crm_notes")
    op.drop_index("ix_crm_note_types_business_id", table_name="crm_note_types")
    op.drop_table("crm_note_types")
