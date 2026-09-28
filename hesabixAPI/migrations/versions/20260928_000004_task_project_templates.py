"""Add native project/task templates.

Revision ID: 20260928_000004_task_project_templates
Revises: 20260926_000003_task_saved_views
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260928_000004_task_project_templates"
down_revision = "20260926_000003_task_saved_views"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "task_project_templates",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column(
            "business_id",
            sa.Integer(),
            sa.ForeignKey("businesses.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("name", sa.String(length=160), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("project_defaults_json", sa.JSON(), nullable=False),
        sa.Column("tasks_json", sa.JSON(), nullable=False),
        sa.Column(
            "is_active",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
        ),
        sa.Column(
            "created_by_user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("NOW()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("NOW()"),
        ),
        sa.UniqueConstraint(
            "business_id",
            "name",
            name="uq_task_project_templates_business_name",
        ),
    )
    op.create_index(
        "ix_task_project_templates_business_id",
        "task_project_templates",
        ["business_id"],
    )
    op.create_index(
        "ix_task_project_templates_business_active",
        "task_project_templates",
        ["business_id", "is_active"],
    )


def downgrade() -> None:
    op.drop_table("task_project_templates")
