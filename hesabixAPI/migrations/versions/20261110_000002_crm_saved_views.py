"""نماهای ذخیره‌شده CRM برای سرنخ و فرصت.

Revision ID: 20261110_000002_crm_saved_views
Revises: 20261110_000001_crm_notes_deal_documents
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261110_000002_crm_saved_views"
down_revision = "20261110_000001_crm_notes_deal_documents"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    if "crm_saved_views" in set(inspector.get_table_names()):
        return
    op.create_table(
        "crm_saved_views",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
        sa.Column("owner_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("entity_type", sa.String(length=20), nullable=False),
        sa.Column("name", sa.String(length=80), nullable=False),
        sa.Column("filters", sa.JSON(), nullable=False),
        sa.Column("is_shared", sa.Boolean(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("business_id", "owner_user_id", "entity_type", "name", name="uq_crm_saved_views_owner_name"),
    )
    op.create_index("idx_crm_saved_views_business_entity", "crm_saved_views", ["business_id", "entity_type"])
    op.create_index("ix_crm_saved_views_owner_user_id", "crm_saved_views", ["owner_user_id"])


def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    if "crm_saved_views" not in set(inspector.get_table_names()):
        return
    op.drop_index("ix_crm_saved_views_owner_user_id", table_name="crm_saved_views")
    op.drop_index("idx_crm_saved_views_business_entity", table_name="crm_saved_views")
    op.drop_table("crm_saved_views")
