"""Add milestone owner.

Revision ID: 20260929_000005_project_milestone_owner
Revises: 20260928_000004_task_project_templates
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260929_000005_project_milestone_owner"
down_revision = "20260928_000004_task_project_templates"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "project_milestones",
        sa.Column(
            "owner_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
    )
    op.create_index(
        "ix_project_milestones_owner_id",
        "project_milestones",
        ["owner_id"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_project_milestones_owner_id",
        table_name="project_milestones",
    )
    op.drop_column("project_milestones", "owner_id")
