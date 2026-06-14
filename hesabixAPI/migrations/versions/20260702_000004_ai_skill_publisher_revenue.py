"""AI skills: publisher revenue split on purchases

Revision ID: 20260702_000004_ai_skill_publisher_revenue
Revises: 20260702_000003_ai_skills_phase4
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260702_000004_ai_skill_publisher_revenue"
down_revision = "20260702_000003_ai_skills_phase4"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "ai_skill_purchases",
        sa.Column("publisher_amount", sa.Numeric(18, 2), nullable=True),
    )
    op.add_column(
        "ai_skill_purchases",
        sa.Column("platform_fee", sa.Numeric(18, 2), nullable=True),
    )
    op.add_column(
        "ai_skill_purchases",
        sa.Column("publisher_wallet_transaction_id", sa.Integer(), nullable=True),
    )
    op.create_foreign_key(
        "fk_ai_skill_purchases_pub_wallet_tx",
        "ai_skill_purchases",
        "wallet_transactions",
        ["publisher_wallet_transaction_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(
        op.f("ix_ai_skill_purchases_publisher_wallet_transaction_id"),
        "ai_skill_purchases",
        ["publisher_wallet_transaction_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        op.f("ix_ai_skill_purchases_publisher_wallet_transaction_id"),
        table_name="ai_skill_purchases",
    )
    op.drop_constraint("fk_ai_skill_purchases_pub_wallet_tx", "ai_skill_purchases", type_="foreignkey")
    op.drop_column("ai_skill_purchases", "publisher_wallet_transaction_id")
    op.drop_column("ai_skill_purchases", "platform_fee")
    op.drop_column("ai_skill_purchases", "publisher_amount")
