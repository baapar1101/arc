"""آیتم‌های حافظه AI (v2)

Revision ID: 20260531_000001_ai_memory_items
Revises: 20260530_000001_ai_memory_structured
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260531_000001_ai_memory_items"
down_revision = "20260530_000001_ai_memory_structured"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "ai_memory_items",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("item_key", sa.String(128), nullable=False),
        sa.Column("category", sa.String(32), nullable=False, server_default="fact"),
        sa.Column("content", sa.Text(), nullable=False, server_default=""),
        sa.Column("structured", sa.Text(), nullable=True),
        sa.Column("source", sa.String(32), nullable=False, server_default="assistant"),
        sa.Column("confidence", sa.String(16), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
        sa.Column("deleted_at", sa.DateTime(), nullable=True),
        sa.UniqueConstraint(
            "business_id",
            "user_id",
            "item_key",
            name="uq_ai_memory_item_business_user_key",
        ),
    )
    op.create_index("ix_ai_memory_items_business_id", "ai_memory_items", ["business_id"])
    op.create_index("ix_ai_memory_items_user_id", "ai_memory_items", ["user_id"])
    op.create_index(
        "ix_ai_memory_items_business_user_deleted",
        "ai_memory_items",
        ["business_id", "user_id", "deleted_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_ai_memory_items_business_user_deleted", table_name="ai_memory_items")
    op.drop_index("ix_ai_memory_items_user_id", table_name="ai_memory_items")
    op.drop_index("ix_ai_memory_items_business_id", table_name="ai_memory_items")
    op.drop_table("ai_memory_items")
