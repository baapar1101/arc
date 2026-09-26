"""Add structured saved task views.

Revision ID: 20260926_000003_task_saved_views
Revises: 20260926_000002_task_management_phase0_completion
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260926_000003_task_saved_views"
down_revision = "20260926_000002_task_management_phase0_completion"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "task_saved_views",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column(
            "business_id",
            sa.Integer(),
            sa.ForeignKey("businesses.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "project_id",
            sa.Integer(),
            sa.ForeignKey("projects.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("view_type", sa.String(length=30), nullable=False, server_default="list"),
        sa.Column("filters_json", sa.JSON(), nullable=False),
        sa.Column("sort_json", sa.JSON(), nullable=False),
        sa.Column("is_shared", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("NOW()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("NOW()")),
        sa.UniqueConstraint(
            "business_id",
            "user_id",
            "name",
            name="uq_task_saved_views_business_user_name",
        ),
    )
    op.create_index("ix_task_saved_views_business_id", "task_saved_views", ["business_id"])
    op.create_index("ix_task_saved_views_user_id", "task_saved_views", ["user_id"])
    op.create_index("ix_task_saved_views_project_id", "task_saved_views", ["project_id"])
    op.create_index(
        "ix_task_saved_views_business_user",
        "task_saved_views",
        ["business_id", "user_id"],
    )
    op.create_index(
        "ix_task_saved_views_business_project",
        "task_saved_views",
        ["business_id", "project_id"],
    )


def downgrade() -> None:
    op.drop_table("task_saved_views")
