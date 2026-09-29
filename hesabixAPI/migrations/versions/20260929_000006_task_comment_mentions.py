"""Add structured task comment mentions.

Revision ID: 20260929_000006_task_comment_mentions
Revises: 20260929_000005_project_milestone_owner
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260929_000006_task_comment_mentions"
down_revision = "20260929_000005_project_milestone_owner"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "task_comment_mentions",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column(
            "business_id",
            sa.Integer(),
            sa.ForeignKey("businesses.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "task_id",
            sa.Integer(),
            sa.ForeignKey("tasks.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "comment_id",
            sa.Integer(),
            sa.ForeignKey("task_comments.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
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
        sa.UniqueConstraint(
            "comment_id",
            "user_id",
            name="uq_task_comment_mentions_comment_user",
        ),
    )
    op.create_index(
        "ix_task_comment_mentions_business_id",
        "task_comment_mentions",
        ["business_id"],
    )
    op.create_index(
        "ix_task_comment_mentions_task_id",
        "task_comment_mentions",
        ["task_id"],
    )
    op.create_index(
        "ix_task_comment_mentions_comment_id",
        "task_comment_mentions",
        ["comment_id"],
    )
    op.create_index(
        "ix_task_comment_mentions_user_id",
        "task_comment_mentions",
        ["user_id"],
    )
    op.create_index(
        "ix_task_comment_mentions_task",
        "task_comment_mentions",
        ["task_id", "comment_id"],
    )
    op.create_index(
        "ix_task_comment_mentions_business_user",
        "task_comment_mentions",
        ["business_id", "user_id"],
    )


def downgrade() -> None:
    op.drop_table("task_comment_mentions")
