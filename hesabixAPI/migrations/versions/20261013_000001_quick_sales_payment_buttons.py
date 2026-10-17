"""Quick-sales configurable payment buttons.

Revision ID: 20261013_000001_quick_sales_payment_buttons
Revises: 20261012_000001_quick_sales_stock_shortage
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261013_000001_quick_sales_payment_buttons"
down_revision = "20261012_000001_quick_sales_stock_shortage"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "quick_sales_payment_buttons",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("scope", sa.String(length=16), nullable=False),
        sa.Column("owner_user_id", sa.Integer(), nullable=True),
        sa.Column("target_type", sa.String(length=24), nullable=False),
        sa.Column("cash_register_id", sa.Integer(), nullable=True),
        sa.Column("bank_account_id", sa.Integer(), nullable=True),
        sa.Column("person_id", sa.Integer(), nullable=True),
        sa.Column("label", sa.String(length=120), nullable=True),
        sa.Column("shortcut", sa.String(length=32), nullable=True),
        sa.Column("position", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_by_user_id", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint("scope IN ('business', 'user')", name="ck_qspb_scope"),
        sa.CheckConstraint(
            "(scope = 'business' AND owner_user_id IS NULL) OR "
            "(scope = 'user' AND owner_user_id IS NOT NULL)",
            name="ck_qspb_scope_owner",
        ),
        sa.CheckConstraint(
            "(target_type = 'cash_register' AND cash_register_id IS NOT NULL "
            "AND bank_account_id IS NULL AND person_id IS NULL) OR "
            "(target_type = 'bank' AND bank_account_id IS NOT NULL "
            "AND cash_register_id IS NULL AND person_id IS NULL) OR "
            "(target_type = 'person' AND person_id IS NOT NULL "
            "AND cash_register_id IS NULL AND bank_account_id IS NULL)",
            name="ck_qspb_exact_target",
        ),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["owner_user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["cash_register_id"], ["cash_registers.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["bank_account_id"], ["bank_accounts.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_qspb_business_active_position",
        "quick_sales_payment_buttons",
        ["business_id", "is_active", "position"],
    )
    op.create_index(
        "ix_quick_sales_payment_buttons_business_id",
        "quick_sales_payment_buttons",
        ["business_id"],
    )
    op.create_index(
        "ix_quick_sales_payment_buttons_owner_user_id",
        "quick_sales_payment_buttons",
        ["owner_user_id"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_quick_sales_payment_buttons_owner_user_id",
        table_name="quick_sales_payment_buttons",
    )
    op.drop_index(
        "ix_qspb_business_active_position",
        table_name="quick_sales_payment_buttons",
    )
    op.drop_index(
        "ix_quick_sales_payment_buttons_business_id",
        table_name="quick_sales_payment_buttons",
    )
    op.drop_table("quick_sales_payment_buttons")
