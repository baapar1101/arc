"""عکس تجمیع فروش شخص برای CRM.

Revision ID: 20261110_000005_crm_person_stats
Revises: 20261110_000004_admin_audit_logs
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261110_000005_crm_person_stats"
down_revision = "20261110_000004_admin_audit_logs"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    if "crm_person_stats" in set(inspector.get_table_names()):
        return
    op.create_table(
        "crm_person_stats",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
        sa.Column("person_id", sa.Integer(), sa.ForeignKey("persons.id", ondelete="CASCADE"), nullable=False),
        sa.Column("sales_total", sa.Numeric(18, 2), nullable=False, server_default="0"),
        sa.Column("returns_total", sa.Numeric(18, 2), nullable=False, server_default="0"),
        sa.Column("net_sales", sa.Numeric(18, 2), nullable=True),
        sa.Column("margin_amount", sa.Numeric(18, 2), nullable=True),
        sa.Column("margin_complete", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("mixed_currency", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("open_document_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("open_remaining", sa.Numeric(18, 2), nullable=True),
        sa.Column("documents_truncated", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("currencies", sa.JSON(), nullable=True),
        sa.Column("repeat_products", sa.JSON(), nullable=True),
        sa.Column("receipt_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("computed_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("business_id", "person_id", name="uq_crm_person_stats_person"),
    )
    op.create_index("idx_crm_person_stats_computed", "crm_person_stats", ["computed_at"])


def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    if "crm_person_stats" not in set(inspector.get_table_names()):
        return
    op.drop_index("idx_crm_person_stats_computed", table_name="crm_person_stats")
    op.drop_table("crm_person_stats")
